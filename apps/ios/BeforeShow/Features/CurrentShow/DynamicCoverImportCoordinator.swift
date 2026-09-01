import Foundation
import PhotosUI
import SwiftData
import SwiftUI

@MainActor
enum DynamicCoverImportCoordinator {
    static func importVideo(
        _ item: PhotosPickerItem,
        for show: Show,
        in modelContext: ModelContext
    ) async throws {
        let expectedCoverID = show.dynamicCover?.id
        let draftID = UUID()
        var committedPath: String?
        var modelSaveCompleted = false
        await LocalMediaCommitGate.shared.acquire()
        defer {
            Task { await LocalMediaCommitGate.shared.release() }
        }

        do {
            guard let imported = try await item.loadTransferable(type: DynamicCoverImportedFile.self) else {
                throw DynamicCoverMediaStoreError.importCancelled
            }
            let staged = try await DynamicCoverMediaStore.shared.stageTransferredFile(imported, draftID: draftID)
            guard !Task.isCancelled else {
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw CancellationError()
            }
            guard show.dynamicCover?.id == expectedCoverID else {
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw DynamicCoverMediaStoreError.staleReplacement
            }
            let committed = try await DynamicCoverMediaStore.shared.commit(
                draftID: draftID,
                showID: show.id,
                video: staged
            )
            committedPath = committed.relativePath
            try Task.checkCancellation()
            let oldCover = show.dynamicCover
            let oldPath = oldCover?.relativePath
            if let oldCover {
                oldCover.replaceVideo(
                    relativePath: committed.relativePath,
                    posterRelativePath: committed.posterRelativePath,
                    contentTypeIdentifier: committed.contentTypeIdentifier,
                    videoDuration: committed.videoDuration
                )
                oldCover.source = .manual
            } else {
                let cover = DynamicCover(
                    id: committed.id,
                    showID: show.id,
                    relativePath: committed.relativePath,
                    posterRelativePath: committed.posterRelativePath,
                    contentTypeIdentifier: committed.contentTypeIdentifier,
                    source: .manual,
                    videoDuration: committed.videoDuration
                )
                cover.show = show
                show.dynamicCover = cover
                modelContext.insert(cover)
            }
            do {
                try modelContext.save()
                modelSaveCompleted = true
            } catch {
                modelContext.rollback()
                try? await DynamicCoverMediaStore.shared.rollbackCommittedFile(relativePath: committed.relativePath)
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw error
            }
            try await DynamicCoverMediaStore.shared.finalizeCommit(draftID: draftID)
            if let oldPath, oldPath != committed.relativePath {
                do {
                    try await DynamicCoverMediaStore.shared.delete(relativePath: oldPath, showID: show.id)
                } catch {
                    ShowAssetCleanupRetry.markDynamicCoverCleanupPending(
                        showID: show.id,
                        relativePath: oldPath
                    )
                }
            }
            // Only reveal the dynamic face after both media and SwiftData are committed.
            DynamicCoverFaceStore.setDynamicFace(true, for: show.id)
        } catch {
            try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
            if let committedPath, !modelSaveCompleted {
                try? await DynamicCoverMediaStore.shared.rollbackCommittedFile(relativePath: committedPath)
            }
            throw error
        }
    }
}
