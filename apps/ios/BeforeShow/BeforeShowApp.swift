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
                    await reconcileAllMemoryMedia(in: modelContainer.mainContext)
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
                        await reconcileAllMemoryMedia(in: modelContainer.mainContext)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

@MainActor
private func reconcileAllMemoryMedia(in modelContext: ModelContext) async {
    do {
        let fragments = try modelContext.fetch(FetchDescriptor<MemoryFragment>())
        var valid: [UUID: [UUID: Set<String>]] = [:]
        for fragment in fragments {
            let paths = Set(
                fragment.mediaItems.flatMap { item in
                    [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
                }
            )
            valid[fragment.showID, default: [:]][fragment.id] = paths
        }
        try await MemoryFragmentMediaStore.shared.reconcileAll(validFilesByShowAndFragment: valid)
        try await MemoryFragmentMediaStore.shared.cleanupStaging(
            olderThan: Date().addingTimeInterval(-86_400)
        )
    } catch {
        // Best-effort recovery; next launch retries.
    }
}
