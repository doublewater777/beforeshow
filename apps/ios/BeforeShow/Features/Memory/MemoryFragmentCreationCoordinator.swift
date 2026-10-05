import Foundation
import SwiftData

@MainActor
enum MemoryFragmentCreationCoordinator {
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
