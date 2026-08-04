import Foundation
import UIKit

enum ShowAssetMediaStoreError: Error, Equatable {
    case unsupportedImage
    case imageEncodingFailed
    case insufficientDiskSpace
    case missingAsset
    case importCancelled

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
        let location = (try? ShowAssetMediaLocation.applicationSupport())
            ?? ShowAssetMediaLocation(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShowAssets", isDirectory: true)
            )
        return ShowAssetMediaStore(location: location)
    }()

    private let location: ShowAssetMediaLocation
    private let fileManager: FileManager
    private var commitGateCount = 0
    private var commitGateWaiters: [CheckedContinuation<Void, Never>] = []

    init(location: ShowAssetMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    func absoluteURL(for relativePath: String) -> URL {
        location.rootDirectory.appendingPathComponent(relativePath)
    }

    func acquireCommitGate() async {
        if commitGateCount == 0 {
            commitGateCount = 1
            return
        }
        await withCheckedContinuation { continuation in
            commitGateWaiters.append(continuation)
            commitGateCount += 1
        }
    }

    func releaseCommitGate() {
        guard commitGateCount > 0 else { return }
        commitGateCount -= 1
        if !commitGateWaiters.isEmpty {
            let waiter = commitGateWaiters.removeFirst()
            waiter.resume()
        }
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
        let image = try decodedImage(from: data)
        let jpegData = try encodedJPEG(from: image)
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
        } catch {
            try? fileManager.removeItem(at: destination)
            throw ShowAssetMediaStoreError.map(error)
        }
        return relativePath
    }

    func delete(relativePath: String) throws {
        let url = absoluteURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            try removeEmptyParents(of: url)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    func deleteShow(_ showID: UUID) throws {
        let showDirectory = location.rootDirectory.appendingPathComponent(showID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: showDirectory)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: location.rootDirectory)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
    }

    /// Keep only files referenced by valid SwiftData assets; drop orphans.
    func reconcile(validRelativePaths: Set<String>) throws {
        do {
            try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
        } catch {
            throw ShowAssetMediaStoreError.map(error)
        }
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var existing: [String] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(
                of: location.rootDirectory.path + "/",
                with: ""
            )
            existing.append(relative)
        }

        for relative in existing where !validRelativePaths.contains(relative) {
            try? delete(relativePath: relative)
        }
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
            let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            guard contents.isEmpty else { return }
            try fileManager.removeItem(at: directory)
            directory = directory.deletingLastPathComponent()
        }
    }
}
