import Foundation
import SwiftData

enum ShowDeletionResult: Equatable {
    case complete(didSync: Bool)
    case mediaCleanupPending(didSync: Bool)

    var didSync: Bool {
        switch self {
        case let .complete(didSync), let .mediaCleanupPending(didSync):
            didSync
        }
    }

    var hasPendingMediaCleanup: Bool {
        if case .mediaCleanupPending = self { return true }
        return false
    }
}

@MainActor
enum ShowDeletionCoordinator {
    static func delete(
        _ show: Show,
        from shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        effects: CurrentShowPostCommitEffects = .live
    ) async throws -> ShowDeletionResult {
        await ShowAssetMediaStore.shared.acquireCommitGate()
        do {
            let coverImageURL = show.coverImageURL
            let showID = show.id
            let targetPersistentID = show.persistentModelID
            let dynamicCoverPath = show.dynamicCover?.relativePath
            let remainingShows = shows.filter { $0.persistentModelID != targetPersistentID }
            let hasRemainingSameBusinessID = remainingShows.contains { $0.id == showID }

            // Manual selection is keyed by the business UUID. If a malformed legacy
            // store contains another row with the same UUID, keep the selection so it
            // can still resolve to the surviving row instead of clearing both logically.
            if selections.first?.selectedShowID == showID && !hasRemainingSameBusinessID {
                selections.first?.clearManualSelection()
            }

            // Show owns fragments/assets/dynamic cover with cascade relationships.
            // Deleting children explicitly before deleting the parent double-mutates the
            // same SwiftData graph and can leave views observing invalidated models.
            modelContext.delete(show)
            let committedState = try ShowMutationCoordinator.commitCurrentShowState(
                shows: remainingShows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )

            var cleanupPending = false
            if !hasRemainingSameBusinessID {
                // Disk stores are keyed only by the business UUID, so they are safe to
                // purge only when no surviving row still owns that UUID. A later delete
                // of the final surviving row will reclaim these files.
                DynamicCoverFaceStore.clear(showID: showID)
                try? await MemoryFragmentMediaStore.shared.deleteShow(showID)
                if let dynamicCoverPath {
                    do {
                        try await DynamicCoverMediaStore.shared.deleteShow(showID)
                    } catch {
                        ShowAssetCleanupRetry.markDynamicCoverCleanupPending(
                            showID: showID,
                            relativePath: dynamicCoverPath
                        )
                        cleanupPending = true
                    }
                }
                ShowAssetCleanupRetry.markShowCleanupPending(showID)
                do {
                    try await ShowAssetMediaStore.shared.deleteShow(showID)
                } catch {
                    cleanupPending = true
                }
                if cleanupPending {
                    ShowAssetCleanupRetry.markShowCleanupPending(showID)
                } else {
                    ShowAssetCleanupRetry.clearShowCleanupPending(showID)
                }
            }

            if let coverImageURL,
               !remainingShows.contains(where: { $0.coverImageURL == coverImageURL }) {
                ShowCoverLocalImageStore.removeManagedLocalImage(at: coverImageURL)
            }
            let didSync = await ShowMutationCoordinator.syncPostCommit(
                committedState,
                in: modelContext,
                effects: effects
            )
            await ShowAssetMediaStore.shared.releaseCommitGate()
            return cleanupPending
                ? .mediaCleanupPending(didSync: didSync)
                : .complete(didSync: didSync)
        } catch {
            modelContext.rollback()
            await ShowAssetMediaStore.shared.releaseCommitGate()
            throw error
        }
    }
}
