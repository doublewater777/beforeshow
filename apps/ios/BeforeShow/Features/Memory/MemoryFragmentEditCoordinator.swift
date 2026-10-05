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

    static func create(
        showID: UUID,
        draftID: UUID,
        media: [MemoryDraftMedia],
        caption: String,
        modelContext: ModelContext,
        now: Date = Date()
    ) async throws -> MemoryFragment {
        let normalizedCaption = try MemoryFragment.normalized(caption)
        guard !media.isEmpty || normalizedCaption != nil else {
            throw MemoryFragmentValidationError.emptyContent
        }
        guard media.count <= MemoryFragment.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }

        let owner = fetchShow(showID, in: modelContext)
        if media.isEmpty {
            let fragment = try makeFragment(
                showID: showID,
                owner: owner,
                caption: caption,
                now: now
            )
            modelContext.insert(fragment)
            try modelContext.save()
            return fragment
        }

        let fragmentID = UUID()
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let committed: [MemoryCommittedMedia]
        do {
            committed = try await MemoryFragmentMediaStore.shared.commit(
                draftID: draftID,
                showID: showID,
                fragmentID: fragmentID,
                media: media
            )
        } catch {
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            throw error
        }
        let committedPaths = committed.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 }
        }
        do {
            let fragment = try makeFragment(
                id: fragmentID,
                showID: showID,
                owner: owner,
                caption: caption,
                now: now
            )
            for (index, item) in committed.enumerated() {
                try fragment.appendMedia(MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration,
                    sortOrder: index
                ))
            }
            modelContext.insert(fragment)
            try modelContext.save()
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
            return fragment
        } catch {
            modelContext.rollback()
            try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            throw error
        }
    }

    static func delete(
        _ fragment: MemoryFragment,
        showID: UUID,
        modelContext: ModelContext
    ) async throws {
        let fragmentID = fragment.id
        modelContext.delete(fragment)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        try? await MemoryFragmentMediaStore.shared.deleteFragment(showID: showID, fragmentID: fragmentID)
    }

    private static func makeFragment(
        id: UUID = UUID(),
        showID: UUID,
        owner: Show?,
        caption: String,
        now: Date
    ) throws -> MemoryFragment {
        let phase = owner.map {
            MemoryFragmentPhase.resolved(at: now, timing: $0.timingFields)
        } ?? .live
        let fragment = try MemoryFragment(
            id: id,
            showID: showID,
            text: caption,
            createdAt: now,
            updatedAt: now,
            phase: phase
        )
        fragment.show = owner
        return fragment
    }

    private static func fetchShow(_ id: UUID, in modelContext: ModelContext) -> Show? {
        var descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
