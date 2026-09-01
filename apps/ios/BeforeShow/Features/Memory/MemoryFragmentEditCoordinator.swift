import Foundation
import SwiftData

@MainActor
enum MemoryFragmentEditCoordinator {
    static func save(
        _ fragment: MemoryFragment,
        showID: UUID,
        fullOrder: [UUID],
        caption: String,
        removedIDs: Set<UUID>,
        additions: [MemoryDraftMedia],
        draftID: UUID,
        modelContext: ModelContext
    ) async throws {
        let normalizedCaption = try MemoryFragment.normalized(caption)
        let remainingExisting = fragment.orderedMediaItems.filter { !removedIDs.contains($0.id) }
        if remainingExisting.isEmpty && additions.isEmpty {
            guard normalizedCaption != nil else { throw MemoryFragmentValidationError.emptyContent }
        }
        guard remainingExisting.count + additions.count <= MemoryFragment.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }

        let removedPaths = fragment.orderedMediaItems
            .filter { removedIDs.contains($0.id) }
            .flatMap { item in [item.relativePath, item.thumbnailRelativePath].compactMap { $0 } }

        var committed: [MemoryCommittedMedia] = []
        var committedPaths: [String] = []
        if !additions.isEmpty {
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            do {
                committed = try await MemoryFragmentMediaStore.shared.commitAdditions(
                    draftID: draftID,
                    showID: showID,
                    fragmentID: fragment.id,
                    media: additions
                )
                committedPaths = committed.flatMap {
                    [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 }
                }
            } catch {
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
                throw error
            }
        }

        do {
            try fragment.updateText(caption)
            let additionItems = committed.map { item in
                MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration,
                    sortOrder: 0
                )
            }
            let removedItems = fragment.orderedMediaItems.filter { removedIDs.contains($0.id) }
            try fragment.applyMediaEdit(
                removingIDs: removedIDs,
                adding: additionItems,
                finalOrder: fullOrder
            )
            for item in removedItems {
                modelContext.delete(item)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            if !committedPaths.isEmpty {
                try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
            }
            if !additions.isEmpty {
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
            }
            throw error
        }

        if !additions.isEmpty {
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
        }
        if !removedPaths.isEmpty {
            Task { try? await MemoryFragmentMediaStore.shared.deleteFiles(relativePaths: removedPaths) }
        }
    }
}
