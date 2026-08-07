import Foundation
import UIKit

enum ShowAssetMediaStoreError: Error, Equatable {
    case unsupportedImage
    case imageEncodingFailed
    case insufficientDiskSpace
    case storageUnavailable
    case missingShow
    case missingAsset
    case importCancelled
    case invalidRelativePath
    case fullCleanupPending

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

/// A single permit for all app-owned media commits. Ticket/timetable assets and
/// memory-fragment media share the same SwiftData show boundary, so operations
/// that delete or reconcile both stores must not interleave with either store's
/// copy-then-save transaction.
actor LocalMediaCommitGate {
    static let shared = LocalMediaCommitGate()

    private var isInUse = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isInUse {
            isInUse = true
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
            isInUse = false
        }
    }
}

struct ShowAssetMediaLocation: Sendable {
    let rootDirectory: URL

    static func applicationSupport() throws -> Self {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return Self(rootDirectory: applicationSupport.appendingPathComponent("ShowAssets", isDirectory: true))
    }
}

/// Local image store for ticket stubs and timetables.
/// Paths are relative to the store root so SwiftData can stay portable across reinstalls of the container.
///
/// Commit gate serializes media writes with launch/active reconciliation so a file
/// cannot be written and then immediately reclaimed before SwiftData saves.
actor ShowAssetMediaStore {
    static let shared: ShowAssetMediaStore = {
        do {
            return ShowAssetMediaStore(location: try ShowAssetMediaLocation.applicationSupport())
        } catch {
            // A temporary directory is not a durable location for a user asset:
            // persist the failure and fail closed instead of reporting a save that
            // may disappear before the next launch.
            return ShowAssetMediaStore(storageError: .storageUnavailable)
        }
    }()

    private let location: ShowAssetMediaLocation
    private let fileManager: FileManager
    private let storageError: ShowAssetMediaStoreError?

    init(location: ShowAssetMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
        self.storageError = nil
    }

    init(storageError: ShowAssetMediaStoreError, fileManager: FileManager = .default) {
        self.location = ShowAssetMediaLocation(
            rootDirectory: fileManager.temporaryDirectory.appendingPathComponent(
                "UnavailableShowAssets",
                isDirectory: true
            )
        )
        self.fileManager = fileManager
        self.storageError = storageError
    }

    func absoluteURL(for relativePath: String) -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            return location.rootDirectory.appendingPathComponent("__invalid-relative-path__")
        }
        return location.rootDirectory.appendingPathComponent(relativePath)
    }

    func absoluteURL(
        for relativePath: String,
        showID: UUID,
        kind: ShowAssetKind
    ) throws -> URL {
        guard ShowAsset.isValidRelativePath(relativePath, showID: showID, kind: kind) else {
            throw ShowAssetMediaStoreError.invalidRelativePath
        }
        return absoluteURL(for: relativePath)
    }

    func rootDirectoryURL() -> URL {
        location.rootDirectory
    }

    func ensureAvailable() throws {
        try ensureStorageAvailable()
    }

    func acquireCommitGate() async {
        await LocalMediaCommitGate.shared.acquire()
    }

    func releaseCommitGate() async {
        await LocalMediaCommitGate.shared.release()
    }

    /// Writes a versioned candidate image. Callers must only delete the previous path
    /// after SwiftData successfully commits the new relative path.
    @discardableResult
    func saveImage(
        data: Data,
        showID: UUID,
        kind: ShowAssetKind,
        assetID: UUID = UUID()
    ) async throws -> String {
        try ensureStorageAvailable()
        guard !ShowAssetCleanupRetry.isFullCleanupPending else {
            throw ShowAssetMediaStoreError.fullCleanupPending
        }
        let image = try decodedImage(from: data)
        let jpegData = try encodedJPEG(from: image)
        try prepareRootDirectory()
        try ensureCapacity(for: Int64(jpegData.count))

        let relativePath = [
            showID.uuidString,
            kind.directoryName,
            "\(assetID.uuidString)-\(UUID().uuidString).jpg"
        ].joined(separator: "/")

        let destination = absoluteURL(for: relativePath)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try jpegData.write(to: destination, options: .atomic)
            try excludeFromBackup(at: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw ShowAssetMediaStoreError.map(error)
        }
        return relativePath
    }

    func delete(relativePath: String) throws {
        try ensureStorageAvailable()
        let url = absoluteURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            try removeEmptyParents(of: url)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    /// Deletes a relative path during orphan reconciliation. It deliberately
    /// remains permissive about ownership because reconciliation has already
    /// enumerated the store root and is the recovery path for invalid records.
    func deleteReconciled(relativePath: String) throws {
        try delete(relativePath: relativePath)
    }

    /// Deletes a path only when it still belongs to the expected show and kind.
    /// Callers operating on a model record must use this overload so corrupted
    /// SwiftData cannot make one show's cleanup remove another show's file.
    func delete(relativePath: String, showID: UUID, kind: ShowAssetKind) throws {
        guard ShowAsset.isValidRelativePath(relativePath, showID: showID, kind: kind) else {
            throw ShowAssetMediaStoreError.invalidRelativePath
        }
        try delete(relativePath: relativePath)
    }

    func deleteShow(_ showID: UUID) throws {
        try ensureStorageAvailable()
        let showDirectory = location.rootDirectory.appendingPathComponent(showID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: showDirectory)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    func deleteAll() throws {
        try ensureStorageAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: location.rootDirectory)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    /// Keep only files referenced by valid SwiftData assets; drop orphans.
    func reconcile(validRelativePaths: Set<String>) throws {
        let existing = try verifiedExistingRelativePaths()

        for relative in existing where !validRelativePaths.contains(relative) {
            try? deleteReconciled(relativePath: relative)
        }
    }

    /// Verifies the durable root is usable and returns the files currently present.
    /// Callers that mutate SwiftData based on file presence must run this first so
    /// a transient storage fault cannot be mistaken for "all files are missing".
    func verifiedExistingRelativePaths() throws -> Set<String> {
        try ensureStorageAvailable()
        try prepareRootDirectory()
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ShowAssetMediaStoreError.storageUnavailable
        }

        var existing: Set<String> = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(
                of: location.rootDirectory.path + "/",
                with: ""
            )
            existing.insert(relative)
        }
        return existing
    }

    private func prepareRootDirectory() throws {
        do {
            try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var root = location.rootDirectory
            try root.setResourceValues(values)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    private func ensureStorageAvailable() throws {
        if let storageError {
            throw storageError
        }
    }

    private func excludeFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try url.setResourceValues(values)
    }

    nonisolated private static func isSafeRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        return !components.isEmpty
            && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private func decodedImage(from data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else {
            throw ShowAssetMediaStoreError.unsupportedImage
        }
        return image
    }

    private func encodedJPEG(from image: UIImage) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = min(image.scale, 2)
        format.opaque = false
        let size = normalizedSize(for: image.size)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = redrawn.jpegData(compressionQuality: 0.88) else {
            throw ShowAssetMediaStoreError.imageEncodingFailed
        }
        return data
    }

    private func normalizedSize(for size: CGSize) -> CGSize {
        let maxEdge: CGFloat = 2400
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return size }
        let scale = maxEdge / longest
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func ensureCapacity(for required: Int64) throws {
        guard let available = availableBytes() else {
            // Fail closed when capacity cannot be measured.
            throw ShowAssetMediaStoreError.insufficientDiskSpace
        }
        if available < required + 2_000_000 {
            throw ShowAssetMediaStoreError.insufficientDiskSpace
        }
    }

    private func availableBytes() -> Int64? {
        // Probe an existing ancestor so capacity works before the root is created.
        var probe = location.rootDirectory
        while !fileManager.fileExists(atPath: probe.path),
              probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        return nil
    }

    private func removeEmptyParents(of fileURL: URL) throws {
        var directory = fileURL.deletingLastPathComponent()
        while directory.path.hasPrefix(location.rootDirectory.path),
              directory.path != location.rootDirectory.path {
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            guard contents.isEmpty else { return }
            try fileManager.removeItem(at: directory)
            directory = directory.deletingLastPathComponent()
        }
    }
}
