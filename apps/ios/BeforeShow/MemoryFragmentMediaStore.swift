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

    static func copied(_ source: URL, contentType: UTType) throws -> MemoryImportedFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = source.pathExtension.isEmpty
            ? (contentType.preferredFilenameExtension ?? "data")
            : source.pathExtension
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        // Capacity must be checked BEFORE the full copy; otherwise a huge video can
        // exhaust disk and leave an orphan temp copy that app-level reconciliation
        // (which only scans the memory root, not this temp dir) would never reclaim.
        // Unknown source size must not bypass the capacity precheck; fail closed.
        guard let requiredBytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) else {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
        do {
            try MemoryCapacity.throwIfInsufficient(at: directory, required: requiredBytes)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch MemoryMediaStoreError.insufficientDiskSpace {
            // No partial copy is created by copyItem on failure, but be defensive.
            try? FileManager.default.removeItem(at: destination)
            throw MemoryMediaStoreError.insufficientDiskSpace
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw MemoryMediaStoreError.map(error)
        }
        // copyItem preserves the source's modificationDate; stamp the import time so
        // cleanupImportTemp ages by when the file was imported, not the original's date
        // (a freshly imported photo taken years ago would otherwise look "stale").
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        return MemoryImportedFile(url: destination, contentType: contentType)
    }
}

enum MemoryMediaStoreError: Error, Equatable {
    case unsupportedMedia
    case imageEncodingFailed
    case missingStagedDraft
    case insufficientDiskSpace
    case storageUnavailable
    case importCancelled

    /// Maps a raw file-system error to `insufficientDiskSpace` when the device is out
    /// of space, otherwise returns the original error. Non-isolated so it can be used
    /// from `MemoryImportedFile.copied` (which runs outside the store actor).
    static func map(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) {
            return Self.insufficientDiskSpace
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            return Self.insufficientDiskSpace
        }
        return error
    }
}

/// Non-isolated disk-capacity checks, usable from `MemoryImportedFile.copied` and
/// other non-actor sites that run before the store actor is involved.
enum MemoryCapacity {
    static func availableBytes(at url: URL, fileManager: FileManager = .default) -> Int64? {
        // `volumeAvailableCapacityForImportantUsageKey` is a volume property, but
        // `URL.resourceValues` fails on a non-existent path. Resolve to the nearest
        // existing ancestor so the check is real instead of silently fail-open.
        var current = url
        while !fileManager.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
        let values = try? current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Throws `insufficientDiskSpace` when `required` bytes are unavailable on the
    /// volume that contains `url`. A missing capacity value (no existing ancestor on
    /// the volume) is treated as insufficient rather than silently allowed.
    static func throwIfInsufficient(at url: URL, required: Int64, fileManager: FileManager = .default) throws {
        guard required > 0 else { return }
        guard let available = availableBytes(at: url, fileManager: fileManager) else {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
        if available < required {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
    }
}

struct MemoryMediaLocation {
    let rootDirectory: URL

    static func applicationSupport(fileManager: FileManager = .default) throws -> Self {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MemoryMediaStoreError.storageUnavailable
        }
        return Self(rootDirectory: applicationSupport.appendingPathComponent("MemoryFragments", isDirectory: true))
    }

    func url(for relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}

actor MemoryFragmentMediaStore {
    static let shared: MemoryFragmentMediaStore = {
        do {
            return MemoryFragmentMediaStore(location: try MemoryMediaLocation.applicationSupport())
        } catch {
            return MemoryFragmentMediaStore(storageError: .storageUnavailable)
        }
    }()

    let location: MemoryMediaLocation
    private let fileManager: FileManager
    private let storageError: MemoryMediaStoreError?

    init(location: MemoryMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
        self.storageError = nil
    }

    init(storageError: MemoryMediaStoreError, fileManager: FileManager = .default) {
        self.location = MemoryMediaLocation(rootDirectory: fileManager.temporaryDirectory.appendingPathComponent("UnavailableMemoryFragments", isDirectory: true))
        self.fileManager = fileManager
        self.storageError = storageError
    }

    /// Shares the app-wide media gate with ticket/timetable assets. Commit paths,
    /// reconciliation, show deletion, and local-data clearing all operate under
    /// the same permit so their SwiftData and file-system boundaries cannot race.
    func acquireCommitGate() async { await LocalMediaCommitGate.shared.acquire() }
    func releaseCommitGate() async { await LocalMediaCommitGate.shared.release() }

    func ensureAvailable() throws {
        if let storageError {
            throw storageError
        }
    }

    func stageCameraPhoto(_ data: Data, draftID: UUID) throws -> MemoryDraftMedia {
        try ensureAvailable()
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
            // Thumbnail generation must be transactional with the original write: if it
            // fails or is cancelled, roll back the original so a failed camera capture
            // leaves no uncounted file in staging.
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
        try ensureAvailable()
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
        // Unknown source size must not bypass the capacity precheck (required <= 0
        // returns early); fail closed instead of copying without a size check.
        guard let requiredBytes = (try? imported.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) else {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
        try ensureAvailableCapacity(forByteCount: requiredBytes)
        do {
            try fileManager.copyItem(at: imported.url, to: destination)
        } catch {
            // Defensive cleanup: a partial copy left by an interrupted copyItem must not
            // become an uncounted staging file.
            try? removeIfPresent(destination)
            throw MemoryMediaStoreError.map(error)
        }

        do {
            // Post-copy work (thumbnail/duration) must roll back the copied staging
            // file on failure; otherwise a failed single-item import leaves an orphan
            // the composer's 20-item cap never accounts for.
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
            // Also remove a partially-generated thumbnail so cancellation/failure after
            // thumbnail generation does not leave an orphan in staging.
            try? removeIfPresent(location.url(for: stagingPath(draftID: draftID, fileName: "\(id.uuidString)-thumbnail.jpg")))
            throw error
        }
    }

    func commit(draftID: UUID, showID: UUID, fragmentID: UUID, media: [MemoryDraftMedia]) throws -> [MemoryCommittedMedia] {
        try ensureAvailable()
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
        try ensureAvailable()
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
        try ensureAvailable()
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    /// Call when SwiftData failed after files were copied to the final location.
    func rollbackCommittedFiles(relativePaths: [String]) throws {
        try ensureAvailable()
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
                let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                try ensureAvailableCapacity(forByteCount: sourceSize)
                try replaceItem(at: destination, with: source)
                copiedURLs.append(destination)

                var thumbnailRelativePath: String?
                if let stagedThumbnail = item.thumbnailStagedRelativePath {
                    let thumbnailSource = location.url(for: stagedThumbnail)
                    guard fileManager.fileExists(atPath: thumbnailSource.path) else {
                        throw MemoryMediaStoreError.missingStagedDraft
                    }
                    let thumbnailPath = "\(finalRelativeDirectory)/\(thumbnailSource.lastPathComponent)"
                    let thumbnailDestination = location.url(for: thumbnailPath)
                    let thumbSize = (try? thumbnailSource.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    try ensureAvailableCapacity(forByteCount: thumbSize)
                    try replaceItem(at: thumbnailDestination, with: thumbnailSource)
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
        try ensureAvailable()
        for path in relativePaths {
            try removeIfPresent(location.url(for: path))
        }
    }

    func discardDraft(_ draftID: UUID) throws {
        try ensureAvailable()
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    /// Removes a transferred temporary file when cancellation happens before staging owns it.
    func discardImportedFile(_ imported: MemoryImportedFile) throws {
        try ensureAvailable()
        try removeIfPresent(imported.url)
    }

    /// Removes a single staged item's original and thumbnail from the staging
    /// directory. Called when the user removes a draft item from the composer so the
    /// 20-item limit reflects real staged files instead of leaving orphan staging
    /// behind (which previously let "import -> delete -> reimport" bypass the cap).
    func removeStagedItem(_ item: MemoryDraftMedia) throws {
        try ensureAvailable()
        try removeIfPresent(location.url(for: item.stagedRelativePath))
        if let thumbnail = item.thumbnailStagedRelativePath {
            try removeIfPresent(location.url(for: thumbnail))
        }
    }

    func deleteFragment(showID: UUID, fragmentID: UUID) throws {
        try ensureAvailable()
        try removeIfPresent(location.url(for: "\(showID.uuidString)/\(fragmentID.uuidString)"))
    }

    func deleteShow(_ showID: UUID) throws {
        try ensureAvailable()
        try removeIfPresent(location.url(for: showID.uuidString))
    }

    func deleteAll() throws {
        try ensureAvailable()
        try removeIfPresent(location.rootDirectory)
    }

    /// Deletes every app-owned memory copy, including PhotosPicker transfer files
    /// that live outside the persistent media root. Used only by the explicit
    /// local-data clear flow and its persisted startup retry.
    func deleteAllIncludingImportTemp() throws {
        try ensureAvailable()
        try deleteAll()
        try deleteAllImportTemp()
    }

    func deleteAllImportTemp() throws {
        try ensureAvailable()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        try removeIfPresent(directory)
    }

    func cleanupStaging(olderThan cutoff: Date) throws {
        try ensureAvailable()
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

    /// Removes stale files left in the PhotosPicker transfer temp directory
    /// (`BeforeShowMemoryImports`). The picker copies each selected file here before
    /// the store is involved, and a failed/cancelled import can leave files behind
    /// that memory reconciliation (which scans the memory root, not this temp dir)
    /// would never reclaim.
    func cleanupImportTemp(olderThan cutoff: Date) throws {
        try ensureAvailable()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for fileURL in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < cutoff }) ?? true {
                try removeIfPresent(fileURL)
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

    /// App-wide recovery: remove orphan show/fragment dirs and unreferenced files.
    func reconcileAll(validFilesByShowAndFragment: [UUID: [UUID: Set<String>]]) throws {
        try ensureAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        for showDirectory in try fileManager.contentsOfDirectory(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            let name = showDirectory.lastPathComponent
            if name == "Staging" {
                continue
            }
            guard let showID = UUID(uuidString: name) else {
                try removeIfPresent(showDirectory)
                continue
            }
            guard let fragments = validFilesByShowAndFragment[showID] else {
                try removeIfPresent(showDirectory)
                continue
            }
            try reconcileFragmentFiles(showID: showID, validFilesByFragmentID: fragments)
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw MemoryMediaStoreError.map(error)
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
