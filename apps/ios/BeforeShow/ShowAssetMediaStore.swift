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

    init(location: ShowAssetMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    func absoluteURL(for relativePath: String) -> URL {
        location.rootDirectory.appendingPathComponent(relativePath)
    }

    /// Imports image data into a final relative path for the show/kind.
    /// Uses a stable path so each show keeps at most one file per kind even if
    /// concurrent saves race; later writes overwrite the same on-disk slot.
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

        // Keep `assetID` in the API for callers that already allocate an ID for the
        // SwiftData row, but pin the file name so uniqueness is filesystem-enforced.
        _ = assetID
        let relativePath = [
            showID.uuidString,
            kind.directoryName,
            "image.jpg"
        ].joined(separator: "/")

        let destination = absoluteURL(for: relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jpegData.write(to: destination, options: .atomic)
        return relativePath
    }

    func delete(relativePath: String) throws {
        let url = absoluteURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        try removeEmptyParents(of: url)
    }

    func deleteShow(_ showID: UUID) throws {
        let showDirectory = location.rootDirectory.appendingPathComponent(showID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }
        try fileManager.removeItem(at: showDirectory)
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        try fileManager.removeItem(at: location.rootDirectory)
    }

    /// Keep only files referenced by valid SwiftData assets; drop orphans.
    func reconcile(validRelativePaths: Set<String>) throws {
        try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
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
        // Normalize orientation by redrawing into a standard bitmap.
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
        guard let available = availableBytes() else { return }
        // Keep a small headroom so the system does not hit zero mid-write.
        if available < required + 2_000_000 {
            throw ShowAssetMediaStoreError.insufficientDiskSpace
        }
    }

    private func availableBytes() -> Int64? {
        let values = try? location.rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
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
