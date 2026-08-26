import AVFoundation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

struct DynamicCoverImportedFile: Transferable, Sendable {
    let url: URL
    let contentType: UTType

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try copied(received.file, contentType: .movie)
        }
    }

    static func copied(_ source: URL, contentType: UTType) throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowDynamicCoverImports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = source.pathExtension.isEmpty
            ? (contentType.preferredFilenameExtension ?? "mov")
            : source.pathExtension
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        guard let requiredBytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) else {
            throw DynamicCoverMediaStoreError.insufficientDiskSpace
        }
        guard requiredBytes <= DynamicCover.maximumFileSize else {
            throw DynamicCoverMediaStoreError.fileTooLarge
        }
        do {
            try DynamicCoverCapacity.throwIfInsufficient(at: directory, required: requiredBytes)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch DynamicCoverMediaStoreError.insufficientDiskSpace {
            try? FileManager.default.removeItem(at: destination)
            throw DynamicCoverMediaStoreError.insufficientDiskSpace
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw DynamicCoverMediaStoreError.map(error)
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        return Self(url: destination, contentType: contentType)
    }
}

enum DynamicCoverMediaStoreError: Error, Equatable {
    case unsupportedVideo
    case invalidDuration
    case missingVideoTrack
    case invalidRelativePath
    case fileTooLarge
    case insufficientDiskSpace
    case storageUnavailable
    case importCancelled
    case staleReplacement

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

enum DynamicCoverErrorMessagePolicy {
    static func message(for error: DynamicCoverMediaStoreError) -> String {
        switch error {
        case .fileTooLarge: return BSLocalization.text("视频太大，最多支持 100 MB。")
        case .invalidDuration: return BSLocalization.text("视频不能超过 15 秒。")
        case .unsupportedVideo, .missingVideoTrack: return BSLocalization.text("这个文件不是可用的视频。")
        case .insufficientDiskSpace: return BSLocalization.text("设备存储空间不足。")
        case .staleReplacement: return BSLocalization.text("现场信息已变化，请重新选择视频。")
        case .importCancelled: return BSLocalization.text("视频导入已取消，请重新选择。")
        default: return BSLocalization.text("视频没有载入，请重试。")
        }
    }
}

/// Non-isolated disk-capacity checks used before a picker transfer is copied.
enum DynamicCoverCapacity {
    static func availableBytes(at url: URL, fileManager: FileManager = .default) -> Int64? {
        var current = url
        while !fileManager.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
        let values = try? current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func throwIfInsufficient(
        at url: URL,
        required: Int64,
        fileManager: FileManager = .default
    ) throws {
        guard required > 0 else { return }
        guard let available = availableBytes(at: url, fileManager: fileManager), available >= required else {
            throw DynamicCoverMediaStoreError.insufficientDiskSpace
        }
    }
}

struct DynamicCoverMediaLocation: Sendable {
    let rootDirectory: URL

    static func applicationSupport(fileManager: FileManager = .default) throws -> Self {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return Self(rootDirectory: applicationSupport.appendingPathComponent("DynamicCovers", isDirectory: true))
    }

    func url(for relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}

/// Local store for a single optional video per show.
/// Files are staged before SwiftData saves and remain show-scoped for reconciliation.
actor DynamicCoverMediaStore {
    static let shared: DynamicCoverMediaStore = {
        do {
            return DynamicCoverMediaStore(location: try DynamicCoverMediaLocation.applicationSupport())
        } catch {
            return DynamicCoverMediaStore(storageError: .storageUnavailable)
        }
    }()

    private let location: DynamicCoverMediaLocation
    private let fileManager: FileManager
    private let storageError: DynamicCoverMediaStoreError?

    init(location: DynamicCoverMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
        self.storageError = nil
    }

    init(storageError: DynamicCoverMediaStoreError, fileManager: FileManager = .default) {
        self.location = DynamicCoverMediaLocation(
            rootDirectory: fileManager.temporaryDirectory.appendingPathComponent(
                "UnavailableDynamicCovers",
                isDirectory: true
            )
        )
        self.fileManager = fileManager
        self.storageError = storageError
    }

    func rootDirectoryURL() -> URL {
        location.rootDirectory
    }

    func acquireCommitGate() async {
        await LocalMediaCommitGate.shared.acquire()
    }

    func releaseCommitGate() async {
        await LocalMediaCommitGate.shared.release()
    }

    func absoluteURL(for relativePath: String) -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            return location.rootDirectory.appendingPathComponent("__invalid-relative-path__")
        }
        return location.url(for: relativePath)
    }

    func absoluteURL(for relativePath: String, showID: UUID) throws -> URL {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        return absoluteURL(for: relativePath)
    }

    func ensureAvailable() throws {
        try ensureStorageAvailable()
    }

    /// Copies and validates one movie into a draft staging directory.
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
        try DynamicCoverCapacity.throwIfInsufficient(at: destination, required: sourceSize)
        do {
            try fileManager.copyItem(at: imported.url, to: destination)
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

    /// Copies a validated staged video into the show directory. Staging remains
    /// until SwiftData saves the corresponding `DynamicCover` record.
    /// Also writes a `<video>-poster.jpg` first frame next to the video; poster
    /// generation failure never blocks the import (the path stays nil).
    func commit(
        draftID: UUID,
        showID: UUID,
        video: DynamicCoverMediaStagedVideo
    ) async throws -> DynamicCoverMediaCommittedVideo {
        guard Self.isValidStagingPath(video.stagedRelativePath, draftID: draftID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        let source = location.url(for: video.stagedRelativePath)
        guard fileManager.fileExists(atPath: source.path) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        let relativePath = "\(showID.uuidString)/\(source.lastPathComponent)"
        let destination = location.url(for: relativePath)
        try prepareRootDirectory()
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try replaceItem(at: destination, with: source)
        let posterRelativePath = await makePosterRelativePath(
            for: destination,
            videoRelativePath: relativePath
        )
        return DynamicCoverMediaCommittedVideo(
            id: video.id,
            relativePath: relativePath,
            posterRelativePath: posterRelativePath,
            contentTypeIdentifier: video.contentTypeIdentifier,
            videoDuration: video.videoDuration
        )
    }

    /// First-frame poster for a committed video, mirroring
    /// `MemoryFragmentMediaStore.makeVideoThumbnail`. Returns nil on any failure.
    private func makePosterRelativePath(for videoURL: URL, videoRelativePath: String) async -> String? {
        let posterRelativePath = Self.posterRelativePath(forVideoRelativePath: videoRelativePath)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        guard let result = try? await generator.image(at: .zero),
              let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.82),
              (try? data.write(to: location.url(for: posterRelativePath), options: .atomic)) != nil else {
            return nil
        }
        return posterRelativePath
    }

    func finalizeCommit(draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    func rollbackCommittedFile(relativePath: String) throws {
        try removeIfPresent(location.url(for: relativePath))
        try removeIfPresent(location.url(for: Self.posterRelativePath(forVideoRelativePath: relativePath)))
    }

    func discardDraft(_ draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    func discardImportedFile(_ imported: DynamicCoverImportedFile) throws {
        try removeIfPresent(imported.url)
    }

    func delete(relativePath: String, showID: UUID) throws {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        try removeIfPresent(location.url(for: relativePath))
        try removeIfPresent(location.url(for: Self.posterRelativePath(forVideoRelativePath: relativePath)))
    }

    func deleteShow(_ showID: UUID) throws {
        try ensureStorageAvailable()
        try removeIfPresent(location.rootDirectory.appendingPathComponent(showID.uuidString, isDirectory: true))
    }

    func deleteAll() throws {
        try ensureStorageAvailable()
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

    func cleanupImportTemp(olderThan cutoff: Date) throws {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("BeforeShowDynamicCoverImports", isDirectory: true)
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

    /// Keeps only paths referenced by valid `DynamicCover` records.
    func verifiedExistingRelativePaths() throws -> Set<String> {
        try ensureStorageAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        var paths = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: location.rootDirectory.path + "/", with: "")
            guard !relativePath.hasPrefix("Staging/") else { continue }
            paths.insert(relativePath)
        }
        return paths
    }

    func reconcile(validRelativePaths: Set<String>) throws {
        try ensureStorageAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: location.rootDirectory.path + "/", with: "")
            guard !relativePath.hasPrefix("Staging/"), !validRelativePaths.contains(relativePath) else { continue }
            try removeIfPresent(fileURL)
        }
        try pruneEmptyDirectories()
    }

    private func pruneEmptyDirectories() throws {
        guard fileManager.fileExists(atPath: location.rootDirectory.path),
              let enumerator = fileManager.enumerator(
                at: location.rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let directories = enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.path.count > $1.path.count }
        for directory in directories where directory.lastPathComponent != "Staging" {
            if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
                try? removeIfPresent(directory)
            }
        }
    }

    private func ensureStorageAvailable() throws {
        if let storageError { throw storageError }
    }

    private func prepareRootDirectory() throws {
        do {
            try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var root = location.rootDirectory
            try root.setResourceValues(values)
        } catch {
            throw DynamicCoverMediaStoreError.map(error)
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var destination = destination
            try destination.setResourceValues(values)
        } catch {
            try? removeIfPresent(destination)
            throw DynamicCoverMediaStoreError.map(error)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func stagingPath(draftID: UUID, fileName: String) -> String {
        "Staging/\(draftID.uuidString)/\(fileName)"
    }

    /// Poster files live next to their video as `<video name>-poster.jpg` so
    /// delete/reconcile can derive them without extra persisted state.
    nonisolated static func posterRelativePath(forVideoRelativePath relativePath: String) -> String {
        "\((relativePath as NSString).deletingPathExtension)-poster.jpg"
    }

    nonisolated private static func isValidStagingPath(_ path: String, draftID: UUID) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return components.count == 3
            && components[0] == "Staging"
            && components[1] == draftID.uuidString
            && !components[2].isEmpty
            && !components.contains(where: { $0 == "." || $0 == ".." })
    }

    private func resolvedContentType(_ imported: DynamicCoverImportedFile) -> UTType {
        if let type = UTType(filenameExtension: imported.url.pathExtension) {
            return type
        }
        return imported.contentType
    }

    nonisolated private static func isSafeRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        return !components.isEmpty
            && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}

struct DynamicCoverMediaStagedVideo: Sendable, Equatable {
    let id: UUID
    let stagedRelativePath: String
    let contentTypeIdentifier: String
    let videoDuration: TimeInterval
}

struct DynamicCoverMediaCommittedVideo: Sendable, Equatable {
    let id: UUID
    let relativePath: String
    let posterRelativePath: String?
    let contentTypeIdentifier: String
    let videoDuration: TimeInterval
}
