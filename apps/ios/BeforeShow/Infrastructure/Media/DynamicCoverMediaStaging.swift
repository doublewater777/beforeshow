import AVFoundation
import Foundation
import UniformTypeIdentifiers

extension DynamicCoverMediaStore {
    /// Moves and validates one app-owned picker transfer into a draft staging directory.
    /// The returned path is temporary until `commit` succeeds.
    func stageTransferredFile(
        _ imported: DynamicCoverImportedFile,
        draftID: UUID
    ) async throws -> DynamicCoverMediaStagedVideo {
        defer { try? fileManager.removeItem(at: imported.url) }
        try ensureStorageAvailable()
        let type = resolvedContentType(imported)
        guard type.conforms(to: .movie) else {
            throw DynamicCoverMediaStoreError.unsupportedVideo
        }
        try Task.checkCancellation()
        guard let sourceSize = (try? imported.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) else {
            throw DynamicCoverMediaStoreError.fileTooLarge
        }
        guard sourceSize <= DynamicCover.maximumFileSize else {
            throw DynamicCoverMediaStoreError.fileTooLarge
        }

        let id = UUID()
        let fileExtension = imported.url.pathExtension.isEmpty
            ? (type.preferredFilenameExtension ?? "mov")
            : imported.url.pathExtension
        let relativePath = stagingPath(draftID: draftID, fileName: "\(id.uuidString).\(fileExtension)")
        let destination = location.url(for: relativePath)
        try prepareRootDirectory()
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let requiresCopyCapacity = DynamicCoverCapacity.requiresCopyCapacity(
            from: imported.url,
            to: destination
        )
        do {
            if requiresCopyCapacity {
                try DynamicCoverCapacity.throwIfInsufficient(at: destination, required: sourceSize)
                try fileManager.copyItem(at: imported.url, to: destination)
            } else {
                // Temp and staging are on the same volume: rename/move takes ownership
                // without allocating another full copy of the source video.
                try fileManager.moveItem(at: imported.url, to: destination)
            }
        } catch {
            try? removeIfPresent(destination)
            throw DynamicCoverMediaStoreError.map(error)
        }

        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: destination)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= DynamicCover.maximumDuration else {
                throw DynamicCoverMediaStoreError.invalidDuration
            }
            let tracks = try await asset.load(.tracks)
            guard tracks.contains(where: { $0.mediaType == .video }) else {
                throw DynamicCoverMediaStoreError.missingVideoTrack
            }
            try Task.checkCancellation()
            return DynamicCoverMediaStagedVideo(
                id: id,
                stagedRelativePath: relativePath,
                contentTypeIdentifier: type.identifier,
                videoDuration: duration
            )
        } catch {
            try? removeIfPresent(destination)
            throw error
        }
    }

    private func stagingPath(draftID: UUID, fileName: String) -> String {
        "Staging/\(draftID.uuidString)/\(fileName)"
    }

    private func resolvedContentType(_ imported: DynamicCoverImportedFile) -> UTType {
        if let type = UTType(filenameExtension: imported.url.pathExtension) {
            return type
        }
        return imported.contentType
    }
}
