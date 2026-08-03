import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct MemoryDraftMedia: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: MemoryMediaKind
    let stagedRelativePath: String
    let thumbnailStagedRelativePath: String?
    let contentTypeIdentifier: String
    let videoDuration: TimeInterval?
}

struct MemoryCommittedMedia: Sendable {
    let id: UUID
    let kind: MemoryMediaKind
    let relativePath: String
    let thumbnailRelativePath: String?
    let contentTypeIdentifier: String
    let videoDuration: TimeInterval?
}

struct MemoryImportedFile: Transferable {
    let url: URL
    let contentType: UTType

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copied(received.file, contentType: .image)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try copied(received.file, contentType: .movie)
        }
    }

    private static func copied(_ source: URL, contentType: UTType) throws -> MemoryImportedFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = source.pathExtension.isEmpty
            ? (contentType.preferredFilenameExtension ?? "data")
            : source.pathExtension
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return MemoryImportedFile(url: destination, contentType: contentType)
    }
}

enum MemoryMediaStoreError: Error {
    case unsupportedMedia
    case imageEncodingFailed
    case missingStagedDraft
    case insufficientDiskSpace
    case importCancelled
}

struct MemoryMediaLocation {
    let rootDirectory: URL

    static func applicationSupport(fileManager: FileManager = .default) -> Self {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        return Self(rootDirectory: applicationSupport.appendingPathComponent("MemoryFragments", isDirectory: true))
    }

    func url(for relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}

actor MemoryFragmentMediaStore {
    static let shared = MemoryFragmentMediaStore(location: .applicationSupport())

    let location: MemoryMediaLocation
    private let fileManager: FileManager

    init(location: MemoryMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    func stageCameraPhoto(_ data: Data, draftID: UUID) throws -> MemoryDraftMedia {
        let id = UUID()
        let relativePath = stagingPath(draftID: draftID, fileName: "\(id.uuidString).jpg")
        let url = location.url(for: relativePath)
        try createParentDirectory(for: url)
        try data.write(to: url, options: .atomic)
        let thumbnail = try makePhotoThumbnail(sourceURL: url, draftID: draftID, mediaID: id)
        return MemoryDraftMedia(
            id: id,
            kind: .photo,
            stagedRelativePath: relativePath,
            thumbnailStagedRelativePath: thumbnail,
            contentTypeIdentifier: UTType.jpeg.identifier,
            videoDuration: nil
        )
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
        try fileManager.copyItem(at: imported.url, to: destination)

        if kind == .photo {
            let thumbnail = try makePhotoThumbnail(sourceURL: destination, draftID: draftID, mediaID: id)
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
        let thumbnail = try await makeVideoThumbnail(asset: asset, draftID: draftID, mediaID: id)
        return MemoryDraftMedia(
            id: id,
            kind: kind,
            stagedRelativePath: relativePath,
            thumbnailStagedRelativePath: thumbnail,
            contentTypeIdentifier: type.identifier,
            videoDuration: duration.isFinite ? duration : nil
        )
    }

    func commit(draftID: UUID, showID: UUID, fragmentID: UUID, media: [MemoryDraftMedia]) throws -> [MemoryCommittedMedia] {
        let finalRelativeDirectory = "\(showID.uuidString)/\(fragmentID.uuidString)"
        let finalDirectory = location.url(for: finalRelativeDirectory)
        return try copyStagingToFinal(
            draftID: draftID,
            finalRelativeDirectory: finalRelativeDirectory,
            finalDirectory: finalDirectory,
            media: media,
            replaceExistingDirectory: true
        )
    }

    func commitAdditions(
        draftID: UUID,
        showID: UUID,
        fragmentID: UUID,
        media: [MemoryDraftMedia]
    ) throws -> [MemoryCommittedMedia] {
        let finalRelativeDirectory = "\(showID.uuidString)/\(fragmentID.uuidString)"
        let finalDirectory = location.url(for: finalRelativeDirectory)
        return try copyStagingToFinal(
            draftID: draftID,
            finalRelativeDirectory: finalRelativeDirectory,
            finalDirectory: finalDirectory,
            media: media,
            replaceExistingDirectory: false
        )
    }

    /// Call only after SwiftData successfully persisted the committed media.
    func finalizeCommit(draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    /// Call when SwiftData failed after files were copied to the final location.
    func rollbackCommittedFiles(relativePaths: [String]) throws {
        try deleteFiles(relativePaths: relativePaths)
    }

    private func copyStagingToFinal(
        draftID: UUID,
        finalRelativeDirectory: String,
        finalDirectory: URL,
        media: [MemoryDraftMedia],
        replaceExistingDirectory: Bool
    ) throws -> [MemoryCommittedMedia] {
        let stagedDirectory = location.url(for: "Staging/\(draftID.uuidString)")
        guard fileManager.fileExists(atPath: stagedDirectory.path) else {
            throw MemoryMediaStoreError.missingStagedDraft
        }

        try fileManager.createDirectory(
            at: finalDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if replaceExistingDirectory, fileManager.fileExists(atPath: finalDirectory.path) {
            try fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.createDirectory(at: finalDirectory, withIntermediateDirectories: true)

        var committed: [MemoryCommittedMedia] = []
        var copiedURLs: [URL] = []
        do {
            for item in media {
                let source = location.url(for: item.stagedRelativePath)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw MemoryMediaStoreError.missingStagedDraft
                }
                let relativePath = "\(finalRelativeDirectory)/\(source.lastPathComponent)"
                let destination = location.url(for: relativePath)
                try fileManager.copyItem(at: source, to: destination)
                copiedURLs.append(destination)

                var thumbnailRelativePath: String?
                if let stagedThumbnail = item.thumbnailStagedRelativePath {
                    let thumbnailSource = location.url(for: stagedThumbnail)
                    guard fileManager.fileExists(atPath: thumbnailSource.path) else {
                        throw MemoryMediaStoreError.missingStagedDraft
                    }
                    let thumbnailPath = "\(finalRelativeDirectory)/\(thumbnailSource.lastPathComponent)"
                    let thumbnailDestination = location.url(for: thumbnailPath)
                    try fileManager.copyItem(at: thumbnailSource, to: thumbnailDestination)
                    copiedURLs.append(thumbnailDestination)
                    thumbnailRelativePath = thumbnailPath
                }

                committed.append(MemoryCommittedMedia(
                    id: item.id,
                    kind: item.kind,
                    relativePath: relativePath,
                    thumbnailRelativePath: thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration
                ))
            }
            // Keep staging until SwiftData save succeeds so failed saves remain retryable.
            return committed
        } catch {
            for copiedURL in copiedURLs {
                try? removeIfPresent(copiedURL)
            }
            throw error
        }
    }

    func deleteFiles(relativePaths: [String]) throws {
        for path in relativePaths {
            try removeIfPresent(location.url(for: path))
        }
    }

    func discardDraft(_ draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    func deleteFragment(showID: UUID, fragmentID: UUID) throws {
        try removeIfPresent(location.url(for: "\(showID.uuidString)/\(fragmentID.uuidString)"))
    }

    func deleteShow(_ showID: UUID) throws {
        try removeIfPresent(location.url(for: showID.uuidString))
    }

    func deleteAll() throws {
        try removeIfPresent(location.rootDirectory)
    }

    func cleanupStaging(olderThan cutoff: Date) throws {
        let staging = location.url(for: "Staging")
        guard fileManager.fileExists(atPath: staging.path) else { return }
        for directory in try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            let values = try directory.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < cutoff }) ?? true {
                try removeIfPresent(directory)
            }
        }
    }

    func cleanupOrphanedFragments(showID: UUID, validFragmentIDs: Set<UUID>) throws {
        let showDirectory = location.url(for: showID.uuidString)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }
        for directory in try fileManager.contentsOfDirectory(
            at: showDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            guard let fragmentID = UUID(uuidString: directory.lastPathComponent),
                  validFragmentIDs.contains(fragmentID) else {
                try removeIfPresent(directory)
                continue
            }
        }
    }

    /// Removes unreferenced files inside valid fragment directories and orphan fragment directories.
    func reconcileFragmentFiles(
        showID: UUID,
        validFilesByFragmentID: [UUID: Set<String>]
    ) throws {
        let showDirectory = location.url(for: showID.uuidString)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }

        for directory in try fileManager.contentsOfDirectory(
            at: showDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            guard let fragmentID = UUID(uuidString: directory.lastPathComponent) else {
                try removeIfPresent(directory)
                continue
            }

            guard let validRelativePaths = validFilesByFragmentID[fragmentID] else {
                try removeIfPresent(directory)
                continue
            }

            let validFileNames = Set(validRelativePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
            for fileURL in try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) where !validFileNames.contains(fileURL.lastPathComponent) {
                try removeIfPresent(fileURL)
            }
        }
    }

    func ensureAvailableCapacity(forByteCount required: Int64) throws {
        guard required > 0 else { return }
        let values = try location.rootDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < required {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
    }

    private func stagingPath(draftID: UUID, fileName: String) -> String {
        "Staging/\(draftID.uuidString)/\(fileName)"
    }

    private func finalPath(from stagedPath: String, finalDirectory: String) -> String {
        "\(finalDirectory)/\(URL(fileURLWithPath: stagedPath).lastPathComponent)"
    }

    private func resolvedContentType(_ imported: MemoryImportedFile) -> UTType {
        if let type = UTType(filenameExtension: imported.url.pathExtension) {
            return type
        }
        return imported.contentType
    }

    private func createParentDirectory(for url: URL) throws {
        try prepareRootDirectory()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func prepareRootDirectory() throws {
        try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = location.rootDirectory
        try root.setResourceValues(values)
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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
        try data.write(to: url, options: .atomic)
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
        try data.write(to: location.url(for: relativePath), options: .atomic)
        return relativePath
    }
}
