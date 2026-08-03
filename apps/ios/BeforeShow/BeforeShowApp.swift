import SwiftUI
import SwiftData
import UserNotifications

@main
struct BeforeShowApp: App {
    @UIApplicationDelegateAdaptor(BeforeShowAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var companionCoordinator = CompanionSharingCoordinator()

    private let modelContainer: ModelContainer = {
        // Companion sharing uses CloudKit CKRecord/CKShare APIs only.
        // Keep SwiftData local — do not mirror the whole store through CloudKit.
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: Show.self,
                CurrentShowSelection.self,
                NotificationSchedulingState.self,
                ShowNotificationScheduleRecord.self,
                MemoryFragment.self,
                MemoryMediaItem.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        UserDefaults.standard.register(defaults: [
            ProEntitlementStorage.appStorageKey: ProEntitlementStorage.encode(
                ProEntitlementStorage.localDebugDefaultEntitlement
            )
        ])
        #endif
        UNUserNotificationCenter.current().delegate = BeforeShowNotificationDelegate.shared
        // Wire CloudKit share acceptance dependencies before any scene callback can race.
        // RootView.onAppear is too late for cold-launch invitation acceptance.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(companionCoordinator)
                .onAppear {
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                    appDelegate.noteDependenciesReady()
                }
                .task {
                    // Ensure delegate wiring even if onAppear ordering is delayed.
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                    appDelegate.noteDependenciesReady()
                    await companionCoordinator.flushPendingAcceptedShares(
                        in: modelContainer.mainContext
                    )
                    await companionCoordinator.refreshAllLinkedShows(
                        in: modelContainer.mainContext
                    )
                    await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: true)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await companionCoordinator.flushPendingAcceptedShares(
                            in: modelContainer.mainContext
                        )
                        await companionCoordinator.refreshAllLinkedShows(
                            in: modelContainer.mainContext
                        )
                        await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: false)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

@MainActor
private func reconcileAllMemoryMedia(in modelContext: ModelContext, includesStagingCleanup: Bool) async {
    // The commit gate makes this pass mutually exclusive with media commits, so the
    // SwiftData snapshot taken here can never be stale relative to a concurrent
    // commit's copy-then-save and delete that commit's just-written files.
    await MemoryFragmentMediaStore.shared.acquireCommitGate()
    do {
        // Enforce the fragment<->show boundary: a fragment whose showID has no
        // corresponding Show is an orphan (its Show was deleted outside the cascade
        // path, or it was created against a fabricated showID). Drop the record and
        // let reconcileAll reclaim its files.
        let realShowIDs = Set(try modelContext.fetch(FetchDescriptor<Show>()).map(\.id))
        let fragments = try modelContext.fetch(FetchDescriptor<MemoryFragment>())
        var valid: [UUID: [UUID: Set<String>]] = [:]
        var removedOrphanRecords = false
        for fragment in fragments {
            guard realShowIDs.contains(fragment.showID) else {
                modelContext.delete(fragment)
                removedOrphanRecords = true
                continue
            }
            let paths = Set(
                fragment.mediaItems.flatMap { item in
                    [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
                }
            )
            valid[fragment.showID, default: [:]][fragment.id] = paths
        }
        if removedOrphanRecords {
            try modelContext.save()
        }
        try await MemoryFragmentMediaStore.shared.reconcileAll(validFilesByShowAndFragment: valid)
        // Staging/import-temp cleanup is intentionally launch-only: running it on every
        // scenePhase=.active could delete a draft still in use by an open composer or
        // retained for retry after a failed save.
        if includesStagingCleanup {
            try await MemoryFragmentMediaStore.shared.cleanupStaging(
                olderThan: Date().addingTimeInterval(-86_400)
            )
            try await MemoryFragmentMediaStore.shared.cleanupImportTemp(
                olderThan: Date().addingTimeInterval(-86_400)
            )
        }
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
    } catch {
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
        // Best-effort recovery; next launch/active retries.
    }
}
