import CoreTransferable
import Foundation
import UniformTypeIdentifiers

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

enum MemoryMediaStoreError: Error {
    case unsupportedMedia
    case imageEncodingFailed
    case missingStagedDraft
    case insufficientDiskSpace
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

    static func requiresCopyCapacity(from source: URL, to destination: URL) -> Bool {
        guard let sourceValues = try? source.resourceValues(forKeys: [.volumeIdentifierKey]),
              let destinationValues = try? destination.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeIdentifierKey]),
              let sourceVolume = sourceValues.volumeIdentifier,
              let destinationVolume = destinationValues.volumeIdentifier else {
            return true
        }
        return !sourceVolume.isEqual(destinationVolume)
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

/// Single-permit async gate that makes media reconciliation and media commits
/// mutually exclusive. Reconciliation builds its on-disk-valid set from a SwiftData
/// snapshot while holding the gate; commits copy staging into the final directory and
/// save to SwiftData while holding the gate. This removes the window in which a
/// reconciliation snapshot taken before a commit's `save()` could delete that commit's
/// just-copied files.
actor MemoryMediaGate {
    private var inUse = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !inUse {
            inUse = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inUse = false
        }
    }
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
