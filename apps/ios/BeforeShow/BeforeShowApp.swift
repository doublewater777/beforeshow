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
                    await companionCoordinator.refreshAllLinkedShows(in: modelContainer.mainContext)
                    await retryPendingShowAssetCleanupIfNeeded(in: modelContainer.mainContext)
                    await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: true)
                    await reconcileAllShowAssets(in: modelContainer.mainContext)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await companionCoordinator.refreshAllLinkedShows(in: modelContainer.mainContext)
                        await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: false)
                        await reconcileAllShowAssets(in: modelContainer.mainContext)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

@MainActor
private func retryPendingShowAssetCleanupIfNeeded(in context: ModelContext) async {
    guard ShowAssetCleanupRetry.isFullCleanupPrepared
            || ShowAssetCleanupRetry.isFullCleanupPending
            || !ShowAssetCleanupRetry.pendingShowCleanupIDs.isEmpty
            || !ShowAssetCleanupRetry.pendingAssets.isEmpty else { return }

    await ShowAssetMediaStore.shared.acquireCommitGate()
    if ShowAssetCleanupRetry.isFullCleanupPrepared {
        let hasPersistedShowData = ((try? context.fetch(FetchDescriptor<Show>()).isEmpty == false) ?? true)
            || ((try? context.fetch(FetchDescriptor<ShowAsset>()).isEmpty == false) ?? true)
        if hasPersistedShowData {
            // The crash happened before the model transaction committed. Do not
            // delete any live ticket/timetable files; the next clear can start fresh.
            ShowAssetCleanupRetry.clearFullCleanupPrepared()
        } else {
            ShowAssetCleanupRetry.markFullCleanupPending()
            ShowAssetCleanupRetry.clearFullCleanupPrepared()
        }
    }
    if ShowAssetCleanupRetry.isFullCleanupPending {
        do {
            try await ShowAssetMediaStore.shared.deleteAll()
            ShowAssetCleanupRetry.clearFullCleanupPending()
        } catch {
            // Keep the marker so the next launch retries the asset root.
        }
    }
    for showID in ShowAssetCleanupRetry.pendingShowCleanupIDs {
        do {
            try await ShowAssetMediaStore.shared.deleteShow(showID)
            ShowAssetCleanupRetry.clearShowCleanupPending(showID)
        } catch {
            // Keep only this show marked for the next retry.
        }
    }
    for pending in ShowAssetCleanupRetry.pendingAssets {
        do {
            try await ShowAssetMediaStore.shared.delete(
                relativePath: pending.relativePath,
                showID: pending.showID,
                kind: pending.kind
            )
            ShowAssetCleanupRetry.clearAssetCleanupPending(pending)
        } catch {
            // Keep this exact path marked for the next retry.
        }
    }
    await ShowAssetMediaStore.shared.releaseCommitGate()
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
    var overflowPaths: [String] = []
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
        if fragment.phaseRawValue == nil {
            fragment.phase = MemoryFragmentPhase.resolved(
                at: fragment.createdAt,
                timing: show.timingFields
            )
            mutated = true
        }
        let overflow = fragment.trimMediaToMaximum()
        if !overflow.isEmpty {
            mutated = true
            for item in overflow {
                overflowPaths.append(contentsOf: [item.relativePath, item.thumbnailRelativePath].compactMap { $0 })
                modelContext.delete(item)
            }
        }
        let paths = Set(
            fragment.mediaItems.flatMap { item in
                [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
            }
        )
        valid[fragment.showID, default: [:]][fragment.id] = paths
    }
    if mutated {
        try modelContext.save()
    }
    if !overflowPaths.isEmpty {
        Task {
            try? await MemoryFragmentMediaStore.shared.deleteFiles(relativePaths: overflowPaths)
        }
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
        let existingRelativePaths = try await ShowAssetMediaStore.shared.verifiedExistingRelativePaths()
        let valid = try reconcileShowAssetShowBoundary(
            in: modelContext,
            existingRelativePaths: existingRelativePaths
        )
        try await ShowAssetMediaStore.shared.reconcile(validRelativePaths: valid)
        await ShowAssetMediaStore.shared.releaseCommitGate()
    } catch {
        modelContext.rollback()
        await ShowAssetMediaStore.shared.releaseCommitGate()
        // Best-effort recovery; next launch/active retries.
    }
}

@MainActor
func reconcileShowAssetShowBoundary(
    in modelContext: ModelContext,
    existingRelativePaths: Set<String>
) throws -> Set<String> {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let assets = try modelContext.fetch(FetchDescriptor<ShowAsset>())
    var valid: Set<String> = []
    var mutated = false
    var keptByKey: [String: ShowAsset] = [:]

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
            if kept.id != asset.id {
                modelContext.delete(asset)
                mutated = true
            }
            continue
        }

        guard existingRelativePaths.contains(asset.relativePath) else {
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
