import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

extension MemoryFragmentMediaStore {
    func stageCameraPhoto(_ data: Data, draftID: UUID) throws -> MemoryDraftMedia {
        let id = UUID()
        let relativePath = stagingPath(draftID: draftID, fileName: "\(id.uuidString).jpg")
        let url = location.url(for: relativePath)
        try createParentDirectory(for: url)
        try ensureAvailableCapacity(forByteCount: Int64(data.count))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MemoryMediaStoreError.map(error)
        }
        do {
            try Task.checkCancellation()
            let thumbnail = try makePhotoThumbnail(sourceURL: url, draftID: draftID, mediaID: id)
            try Task.checkCancellation()
            return MemoryDraftMedia(
                id: id,
                kind: .photo,
                stagedRelativePath: relativePath,
                thumbnailStagedRelativePath: thumbnail,
                contentTypeIdentifier: UTType.jpeg.identifier,
                videoDuration: nil
            )
        } catch {
            try? removeIfPresent(url)
            try? removeIfPresent(location.url(for: stagingPath(draftID: draftID, fileName: "\(id.uuidString)-thumbnail.jpg")))
            throw error
        }
    }

    func stageTransferredFile(_ imported: MemoryImportedFile, draftID: UUID) async throws -> MemoryDraftMedia {
        defer { try? fileManager.removeItem(at: imported.url) }
        let id = UUID()
        let type = resolvedContentType(imported)
        let kind: MemoryMediaKind
        if type.conforms(to: .image) {
            kind = .photo
        } else if type.conforms(to: .movie) {
            kind = .video
        } else {
            throw MemoryMediaStoreError.unsupportedMedia
        }

        let fileExtension = imported.url.pathExtension.isEmpty
            ? (type.preferredFilenameExtension ?? (kind == .photo ? "jpg" : "mov"))
            : imported.url.pathExtension
        let relativePath = stagingPath(draftID: draftID, fileName: "\(id.uuidString).\(fileExtension)")
        let destination = location.url(for: relativePath)
        try createParentDirectory(for: destination)
        try Task.checkCancellation()
        let requiresCopyCapacity = MemoryCapacity.requiresCopyCapacity(
            from: imported.url,
            to: destination
        )
        do {
            if requiresCopyCapacity {
                guard let requiredBytes = (try? imported.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init) else {
                    throw MemoryMediaStoreError.insufficientDiskSpace
                }
                try ensureAvailableCapacity(forByteCount: requiredBytes)
                try fileManager.copyItem(at: imported.url, to: destination)
            } else {
                try fileManager.moveItem(at: imported.url, to: destination)
            }
        } catch {
            try? removeIfPresent(destination)
            throw MemoryMediaStoreError.map(error)
        }

        do {
            try Task.checkCancellation()
            if kind == .photo {
                let thumbnail = try makePhotoThumbnail(sourceURL: destination, draftID: draftID, mediaID: id)
                try Task.checkCancellation()
                return MemoryDraftMedia(
                    id: id,
                    kind: kind,
                    stagedRelativePath: relativePath,
                    thumbnailStagedRelativePath: thumbnail,
                    contentTypeIdentifier: type.identifier,
                    videoDuration: nil
                )
            }

            let asset = AVURLAsset(url: destination)
            let duration = try await asset.load(.duration).seconds
            try Task.checkCancellation()
            let thumbnail = try await makeVideoThumbnail(asset: asset, draftID: draftID, mediaID: id)
            try Task.checkCancellation()
            return MemoryDraftMedia(
                id: id,
                kind: kind,
                stagedRelativePath: relativePath,
                thumbnailStagedRelativePath: thumbnail,
                contentTypeIdentifier: type.identifier,
                videoDuration: duration.isFinite ? duration : nil
            )
        } catch {
            try? removeIfPresent(destination)
            try? removeIfPresent(location.url(for: stagingPath(draftID: draftID, fileName: "\(id.uuidString)-thumbnail.jpg")))
            throw error
        }
    }

    private func stagingPath(draftID: UUID, fileName: String) -> String {
        "Staging/\(draftID.uuidString)/\(fileName)"
    }

    private func resolvedContentType(_ imported: MemoryImportedFile) -> UTType {
        if let type = UTType(filenameExtension: imported.url.pathExtension) {
            return type
        }
        return imported.contentType
    }

    private func makePhotoThumbnail(sourceURL: URL, draftID: UUID, mediaID: UUID) throws -> String {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_200
              ] as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
            throw MemoryMediaStoreError.imageEncodingFailed
        }
        let relativePath = stagingPath(draftID: draftID, fileName: "\(mediaID.uuidString)-thumbnail.jpg")
        let url = location.url(for: relativePath)
        try ensureAvailableCapacity(forByteCount: Int64(data.count))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MemoryMediaStoreError.map(error)
        }
        return relativePath
    }

    private func makeVideoThumbnail(asset: AVURLAsset, draftID: UUID, mediaID: UUID) async throws -> String {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        let result = try await generator.image(at: .zero)
        guard let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.82) else {
            throw MemoryMediaStoreError.imageEncodingFailed
        }
        let relativePath = stagingPath(draftID: draftID, fileName: "\(mediaID.uuidString)-thumbnail.jpg")
        let url = location.url(for: relativePath)
        try ensureAvailableCapacity(forByteCount: Int64(data.count))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MemoryMediaStoreError.map(error)
        }
        return relativePath
    }
}
