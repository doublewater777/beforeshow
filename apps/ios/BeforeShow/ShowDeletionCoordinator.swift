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
            if selections.first?.selectedShowID == show.id {
                selections.first?.clearManualSelection()
            }

            let showID = show.id
            let dynamicCoverPath = show.dynamicCover?.relativePath
            let remainingShows = shows.filter { $0.id != showID }
            let fragments = try modelContext.fetch(
                FetchDescriptor<MemoryFragment>(predicate: #Predicate { $0.showID == showID })
            )
            for fragment in fragments {
                modelContext.delete(fragment)
            }
            let assets = try modelContext.fetch(
                FetchDescriptor<ShowAsset>(predicate: #Predicate { $0.showID == showID })
            )
            for asset in assets {
                modelContext.delete(asset)
            }
            modelContext.delete(show)
            let committedState = try ShowMutationCoordinator.commitCurrentShowState(
                shows: remainingShows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )

            DynamicCoverFaceStore.clear(showID: showID)
            try? await MemoryFragmentMediaStore.shared.deleteShow(showID)
            var cleanupPending = false
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
