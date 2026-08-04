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
                ShowAsset.self,
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
                    await reconcileAllShowAssets(in: modelContainer.mainContext)
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
                        await reconcileAllShowAssets(in: modelContainer.mainContext)
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
        let valid = try reconcileMemoryFragmentShowBoundary(in: modelContext)
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

/// Enforces the fragment<->show boundary against the current SwiftData state and
/// returns the on-disk-valid file map for media reconciliation.
///
/// - Fragments whose `showID` has no corresponding `Show` are orphan records (their
///   Show was deleted, or they were created against a fabricated showID) and are
///   removed here so `reconcileAll` can reclaim their files.
/// - Fragments that predate the `show` relationship (existing production data has
///   `showID` but `show == nil`) are backfilled with the relationship so the cascade
///   delete rule applies to them too.
///
/// Extracted from `reconcileAllMemoryMedia` so this production seam is unit-testable
/// without touching the media store actor or disk.
@MainActor
func reconcileMemoryFragmentShowBoundary(in modelContext: ModelContext) throws -> [UUID: [UUID: Set<String>]] {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let fragments = try modelContext.fetch(FetchDescriptor<MemoryFragment>())
    var valid: [UUID: [UUID: Set<String>]] = [:]
    var mutated = false
    for fragment in fragments {
        guard let show = showsByID[fragment.showID] else {
            modelContext.delete(fragment)
            mutated = true
            continue
        }
        if fragment.show == nil {
            fragment.show = show
            mutated = true
        }
        let paths = Set(
            fragment.mediaItems.flatMap { item in
                [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
            }
        )
        valid[fragment.showID, default: [:]][fragment.id] = paths
    }
    if mutated {
        try saveModelContextRollingBackOnFailure(modelContext)
    }
    return valid
}

@MainActor
func saveModelContextRollingBackOnFailure(
    _ modelContext: ModelContext,
    save: () throws -> Void
) throws {
    do {
        try save()
    } catch {
        modelContext.rollback()
        throw error
    }
}

@MainActor
func saveModelContextRollingBackOnFailure(_ modelContext: ModelContext) throws {
    try saveModelContextRollingBackOnFailure(modelContext) {
        try modelContext.save()
    }
}


@MainActor
private func reconcileAllShowAssets(in modelContext: ModelContext) async {
    await ShowAssetMediaStore.shared.acquireCommitGate()
    do {
        let rootDirectory = await ShowAssetMediaStore.shared.rootDirectoryURL()
        let valid = try reconcileShowAssetShowBoundary(
            in: modelContext,
            assetRootDirectory: rootDirectory
        )
        try await ShowAssetMediaStore.shared.reconcile(validRelativePaths: valid)
        await ShowAssetMediaStore.shared.releaseCommitGate()
    } catch {
        modelContext.rollback()
        await ShowAssetMediaStore.shared.releaseCommitGate()
        // Best-effort recovery; next launch/active retries.
    }
}

/// Enforces the asset<->show boundary and returns valid on-disk relative paths.
/// Also collapses duplicate (showID, kind) rows and drops records whose files are missing.
@MainActor
func reconcileShowAssetShowBoundary(
    in modelContext: ModelContext,
    assetRootDirectory: URL
) throws -> Set<String> {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let assets = try modelContext.fetch(FetchDescriptor<ShowAsset>())
    var valid: Set<String> = []
    var mutated = false
    var keptByKey: [String: ShowAsset] = [:]

    // Prefer newest updatedAt when collapsing historical duplicates.
    let ordered = assets.sorted {
        if $0.updatedAt == $1.updatedAt {
            return $0.id.uuidString > $1.id.uuidString
        }
        return $0.updatedAt > $1.updatedAt
    }

    for asset in ordered {
        guard let show = showsByID[asset.showID] else {
            modelContext.delete(asset)
            mutated = true
            continue
        }
        if asset.show?.id != show.id {
            asset.show = show
            mutated = true
        }
        if ShowAssetKind(rawValue: asset.kindRawValue) == nil {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        guard ShowAsset.isValidRelativePath(
            asset.relativePath,
            showID: asset.showID,
            kind: asset.kind
        ) else {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        let key = ShowAsset.makeUniqueKey(showID: asset.showID, kind: asset.kind)
        if asset.repairUniqueKeyIfNeeded() {
            mutated = true
        }
        if let kept = keptByKey[key] {
            // Keep newest; drop older duplicate.
            if kept.id != asset.id {
                modelContext.delete(asset)
                mutated = true
            }
            continue
        }

        // Drop records whose files disappeared so UI returns to "未添加".
        let fileURL = assetRootDirectory.appendingPathComponent(asset.relativePath)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        keptByKey[key] = asset
        valid.insert(asset.relativePath)
    }
    if mutated {
        try saveModelContextRollingBackOnFailure(modelContext)
    }
    return valid
}
