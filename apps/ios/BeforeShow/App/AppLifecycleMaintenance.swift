import Foundation
import SwiftData

@MainActor
func synchronizeFreeShowCapacity(
    in modelContext: ModelContext,
    entitlement: ProEntitlementState? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
) {
    guard let shows = try? modelContext.fetch(FetchDescriptor<Show>()) else { return }
    let resolvedEntitlement = entitlement ?? ProEntitlementStorage.decode(
        UserDefaults.standard.string(forKey: ProEntitlementStorage.appStorageKey) ?? ""
    )
    ProFeatureGate().synchronizeFreeCapacity(
        from: shows,
        entitlement: resolvedEntitlement,
        now: now,
        calendar: calendar
    )
}

enum ForegroundMediaMaintenancePolicy {
    static let minimumInterval: TimeInterval = 10 * 60

    static func shouldRun(
        lastRun: Date?,
        isRunning: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !isRunning else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minimumInterval
    }
}

@MainActor
func retryPendingShowAssetCleanupIfNeeded(in context: ModelContext) async {
    guard ShowAssetCleanupRetry.isFullCleanupPrepared
            || ShowAssetCleanupRetry.isFullCleanupPending
            || !ShowAssetCleanupRetry.pendingShowCleanupIDs.isEmpty
            || !ShowAssetCleanupRetry.pendingAssets.isEmpty
            || !ShowAssetCleanupRetry.pendingDynamicCovers.isEmpty else { return }

    await ShowAssetMediaStore.shared.acquireCommitGate()
    if ShowAssetCleanupRetry.isFullCleanupPrepared {
        let hasPersistedShowData = ((try? context.fetch(FetchDescriptor<Show>()).isEmpty == false) ?? true)
            || ((try? context.fetch(FetchDescriptor<ShowAsset>()).isEmpty == false) ?? true)
            || ((try? context.fetch(FetchDescriptor<DynamicCover>()).isEmpty == false) ?? true)
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
        DynamicCoverFaceStore.clearAll()
        await retryPendingFullCleanup(
            deleteShowAssets: {
                try await ShowAssetMediaStore.shared.deleteAll()
            },
            deleteDynamicCovers: {
                try await DynamicCoverMediaStore.shared.deleteAll()
            }
        )
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
    for pending in ShowAssetCleanupRetry.pendingDynamicCovers {
        do {
            try await DynamicCoverMediaStore.shared.delete(
                relativePath: pending.relativePath,
                showID: pending.showID
            )
            ShowAssetCleanupRetry.clearDynamicCoverCleanupPending(pending)
        } catch {
            // Keep this exact path marked for the next retry.
        }
    }
    await ShowAssetMediaStore.shared.releaseCommitGate()
}

@MainActor
func retryPendingFullCleanup(
    deleteShowAssets: @escaping () async throws -> Void,
    deleteDynamicCovers: @escaping () async throws -> Void
) async {
    guard ShowAssetCleanupRetry.isFullCleanupPending else { return }

    var cleanupSucceeded = true
    do {
        try await deleteShowAssets()
    } catch {
        cleanupSucceeded = false
    }
    do {
        try await deleteDynamicCovers()
    } catch {
        cleanupSucceeded = false
    }
    if cleanupSucceeded {
        ShowAssetCleanupRetry.clearFullCleanupPending()
    }
}

@MainActor
func reconcileAllMemoryMedia(in modelContext: ModelContext, includesStagingCleanup: Bool) async {
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

@MainActor
func reconcileAllShowAssets(in modelContext: ModelContext) async {
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
func reconcileAllDynamicCovers(
    in modelContext: ModelContext,
    includesStagingCleanup: Bool
) async {
    await LocalMediaCommitGate.shared.acquire()
    defer { Task { await LocalMediaCommitGate.shared.release() } }
    do {
        let existingPaths = try await DynamicCoverMediaStore.shared.verifiedExistingRelativePaths()
        let validPaths = try reconcileDynamicCoverModelBoundary(
            in: modelContext,
            existingRelativePaths: existingPaths
        )
        try await DynamicCoverMediaStore.shared.reconcile(validRelativePaths: validPaths)
        if includesStagingCleanup {
            try await DynamicCoverMediaStore.shared.cleanupStaging(
                olderThan: Date().addingTimeInterval(-86_400)
            )
            try await DynamicCoverMediaStore.shared.cleanupImportTemp(
                olderThan: Date().addingTimeInterval(-86_400)
            )
        }
    } catch {
        modelContext.rollback()
    }
}
