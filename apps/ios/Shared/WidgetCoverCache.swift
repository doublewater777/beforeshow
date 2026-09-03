import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Widget Cover Cache
// Covers are hashed by source URL and shared by the app, widget and Live Activity.
// Refresh never prunes non-empty sources; the app prunes only after it has resolved
// every surface that currently needs a cover.

enum WidgetCoverCache {
    fileprivate static let maxPixelDimension: CGFloat = 400
    fileprivate static let liveActivityMaxPixelDimension: CGFloat = 120
    fileprivate static let maxDownloadBytes = 100 * 1_024 * 1_024

    private static let mutator = CoverCacheMutator()

    static func cachedCoverPath(matching source: String?) -> String? {
        guard let source,
              let filename = freshCoverFilename(for: source),
              let url = coverFileURL(filename: filename),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url.path
    }

    static func freshCoverFilename(for source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              markerMatches(source: trimmed),
              let cacheURL = coverFileURL(for: trimmed),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        return cacheURL.lastPathComponent
    }

    static func freshLiveActivityCoverFilename(for source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              markerMatches(source: trimmed),
              let url = coverFileURL(filename: liveActivityFilename(for: trimmed)),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url.lastPathComponent
    }

    private static func markerMatches(source: String) -> Bool {
        guard let markerURL = markerFileURL(for: source),
              let cached = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return false
        }
        return cached == source
    }

    static func refresh(for source: String?) async {
        await mutator.refresh(for: source)
    }

    /// Compatibility helper for single-surface call sites.
    static func pruneCovers(except currentSource: String?) {
        let source = currentSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        pruneCovers(keeping: Set([source].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }))
    }

    /// Keeps the union of every currently resolved surface source. This is required
    /// now that Widget may show a user-owned historical Current Show while Live
    /// Activity follows a different live/upcoming show.
    static func pruneCovers(keeping sources: Set<String>) {
        let normalized = Set(
            sources
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalized.isEmpty else {
            clearHashedCovers()
            clearLegacyFixedCover()
            return
        }
        pruneCoversKeeping(normalized)
        clearLegacyFixedCover()
    }

    // MARK: - Paths

    fileprivate static func coverFileURL(for source: String) -> URL? {
        coverFileURL(filename: filename(for: source))
    }

    fileprivate static func coverFileURL(filename: String) -> URL? {
        WidgetSnapshotStore.containerURL?
            .appendingPathComponent(filename, isDirectory: false)
    }

    fileprivate static func markerFileURL(for source: String) -> URL? {
        coverFileURL(for: source)?.appendingPathExtension("source")
    }

    static func filename(for source: String) -> String {
        let digest = stableHash(source.trimmingCharacters(in: .whitespacesAndNewlines))
        return "cover-\(digest).jpg"
    }

    static func liveActivityFilename(for source: String) -> String {
        let digest = stableHash(source.trimmingCharacters(in: .whitespacesAndNewlines))
        return "cover-\(digest)-la.jpg"
    }

    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    fileprivate static func clearLegacyFixedCover() {
        guard let base = WidgetSnapshotStore.containerURL else { return }
        let legacy = base.appendingPathComponent(WidgetSnapshotStore.legacyCoverCacheFilename, isDirectory: false)
        let legacyMarker = legacy.appendingPathExtension("source")
        try? FileManager.default.removeItem(at: legacy)
        try? FileManager.default.removeItem(at: legacyMarker)
    }

    private static func clearHashedCovers() {
        guard let base = WidgetSnapshotStore.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return
        }
        for file in files where file.hasPrefix("cover-") {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(file, isDirectory: false))
        }
    }

    private static func pruneCoversKeeping(_ sources: Set<String>) {
        guard let base = WidgetSnapshotStore.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return
        }
        var keep = Set<String>()
        for source in sources {
            keep.insert(filename(for: source))
            keep.insert(liveActivityFilename(for: source))
            keep.insert(filename(for: source) + ".source")
        }
        for file in files where file.hasPrefix("cover-") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(file, isDirectory: false))
        }
    }

    // MARK: - Image processing

    fileprivate static func downsampledJPEG(from data: Data, maxPixel: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(destination, cgImage, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }
}

private actor CoverCacheMutator {
    private var generation: UInt64 = 0

    func refresh(for source: String?) async {
        generation &+= 1
        let ticket = generation

        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            guard ticket == generation else { return }
            WidgetCoverCache.pruneCovers(keeping: [])
            return
        }

        if WidgetCoverCache.freshCoverFilename(for: trimmed) != nil,
           WidgetCoverCache.freshLiveActivityCoverFilename(for: trimmed) != nil {
            return
        }

        guard let remoteURL = URL(string: trimmed),
              let cacheURL = WidgetCoverCache.coverFileURL(for: trimmed),
              let liveActivityURL = WidgetCoverCache.coverFileURL(
                filename: WidgetCoverCache.liveActivityFilename(for: trimmed)
              ),
              let markerURL = WidgetCoverCache.markerFileURL(for: trimmed) else {
            return
        }

        do {
            let data: Data
            if remoteURL.isFileURL {
                data = try Data(contentsOf: remoteURL)
            } else {
                let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
                guard ticket == generation else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    #if DEBUG
                    print("[WidgetCoverCache] non-200 for \(trimmed)")
                    #endif
                    return
                }
                guard let mime = http.mimeType, mime.hasPrefix("image/") else {
                    #if DEBUG
                    print("[WidgetCoverCache] unexpected MIME: \(http.mimeType ?? "nil")")
                    #endif
                    return
                }
                data = try Data(contentsOf: tempURL)
            }

            let fileSize = data.count
            guard fileSize > 0, fileSize <= WidgetCoverCache.maxDownloadBytes else {
                #if DEBUG
                print("[WidgetCoverCache] payload too large: \(fileSize) bytes")
                #endif
                return
            }
            guard let jpeg = WidgetCoverCache.downsampledJPEG(
                from: data,
                maxPixel: WidgetCoverCache.maxPixelDimension
            ),
                  let liveActivityJPEG = WidgetCoverCache.downsampledJPEG(
                    from: data,
                    maxPixel: WidgetCoverCache.liveActivityMaxPixelDimension
                  ) else {
                #if DEBUG
                print("[WidgetCoverCache] downsample failed for \(trimmed)")
                #endif
                return
            }

            guard ticket == generation else { return }
            try jpeg.write(to: cacheURL, options: .atomic)
            try liveActivityJPEG.write(to: liveActivityURL, options: .atomic)
            try trimmed.write(to: markerURL, atomically: true, encoding: .utf8)
            WidgetCoverCache.clearLegacyFixedCover()
        } catch {
            #if DEBUG
            print("[WidgetCoverCache] refresh failed: \(error)")
            #endif
        }
    }
}
