import CoreTransferable
import Foundation
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
