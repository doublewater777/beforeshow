import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - Widget Cover Cache
// Covers are hashed by source URL and shared by the app, widget and Live Activity.
// Refresh never prunes non-empty sources; the app prunes only after it has resolved
// every surface that currently needs a cover.

enum WidgetCoverCache {
    fileprivate static let maxPixelDimension: CGFloat = 400
    /// Covers the largest Live Activity presentation (lock screen cover 72×96pt @3x).
    static let liveActivityMaxPixelDimension: CGFloat = 288
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

    /// The app can seed shared thumbnails from an original it already downloaded.
    static func store(_ data: Data, for source: String) async {
        await mutator.store(data, for: source.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Pruning and download cancellation share an owner so an obsolete request
    /// cannot restore files after the app switches its retained surface sources.
    static func pruneCovers(keeping sources: Set<String>) async {
        let normalized = Set(sources.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        await mutator.prune(keeping: normalized)
    }

    fileprivate static func pruneFiles(keeping sources: Set<String>) {
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
        // Suffix tracks liveActivityMaxPixelDimension so older, smaller files are rebuilt and pruned.
        return "cover-\(digest)-la288.jpg"
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

    // MARK: - Live Activity presentation

    /// Live Activity / Dynamic Island show a gray placeholder (or nothing) when an image is
    /// larger than its presentation. Render exactly the presented point size at @3x,
    /// aspect-filling (cropping, never stretching) the source.
    static func liveActivityImage(contentsOf url: URL, filling pointSize: CGSize) -> UIImage? {
        guard pointSize.width > 0, pointSize.height > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: liveActivityMaxPixelDimension
              ] as CFDictionary) else {
            return nil
        }
        let sourceSize = CGSize(width: decoded.width, height: decoded.height)
        let fill = max(pointSize.width / sourceSize.width, pointSize.height / sourceSize.height)
        let drawn = CGSize(width: sourceSize.width * fill, height: sourceSize.height * fill)
        let origin = CGPoint(x: (pointSize.width - drawn.width) / 2, y: (pointSize.height - drawn.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(size: pointSize, format: format).image { _ in
            UIImage(cgImage: decoded).draw(in: CGRect(origin: origin, size: drawn))
        }
    }

    static func liveActivityImage(filename: String, filling pointSize: CGSize) -> UIImage? {
        guard let url = coverFileURL(filename: filename) else { return nil }
        return liveActivityImage(contentsOf: url, filling: pointSize)
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
    private var inFlight: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    func refresh(for source: String?) async {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !isReady(trimmed) else { return }
        if let download = inFlight[trimmed] {
            await download.task.value
            return
        }
        let id = UUID()
        let task = Task { await download(trimmed) }
        inFlight[trimmed] = (id, task)
        await task.value
        if inFlight[trimmed]?.id == id { inFlight[trimmed] = nil }
    }

    func prune(keeping sources: Set<String>) {
        var retained = sources
        // Listening changes independently while a show sync prepares its artwork.
        // Read its durable source at the mutation boundary, not from an older request.
        if let listening = WidgetListeningStore.read(),
           listening.showID == WidgetSnapshotStore.read()?.showID,
           let source = listening.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty {
            retained.insert(source)
        }
        for (source, download) in inFlight where !retained.contains(source) {
            download.task.cancel()
            inFlight[source] = nil
        }
        WidgetCoverCache.pruneFiles(keeping: retained)
    }

    private func isReady(_ source: String) -> Bool {
        WidgetCoverCache.freshCoverFilename(for: source) != nil
            && WidgetCoverCache.freshLiveActivityCoverFilename(for: source) != nil
    }

    private func download(_ source: String) async {
        guard let url = URL(string: source) else { return }
        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let mime = http.mimeType, mime.hasPrefix("image/") else { return }
                data = try Data(contentsOf: tempURL)
            }
            guard !Task.isCancelled else { return }
            store(data, for: source)
        } catch {
            #if DEBUG
            print("[WidgetCoverCache] refresh failed: \(error)")
            #endif
        }
    }

    func store(_ data: Data, for source: String) {
        guard !source.isEmpty, !isReady(source),
              !data.isEmpty, data.count <= WidgetCoverCache.maxDownloadBytes,
              let cacheURL = WidgetCoverCache.coverFileURL(for: source),
              let liveActivityURL = WidgetCoverCache.coverFileURL(
                filename: WidgetCoverCache.liveActivityFilename(for: source)
              ),
              let markerURL = WidgetCoverCache.markerFileURL(for: source),
              let jpeg = WidgetCoverCache.downsampledJPEG(
                from: data, maxPixel: WidgetCoverCache.maxPixelDimension
              ),
              let liveActivityJPEG = WidgetCoverCache.downsampledJPEG(
                from: data, maxPixel: WidgetCoverCache.liveActivityMaxPixelDimension
              ) else { return }
        do {
            try jpeg.write(to: cacheURL, options: .atomic)
            try liveActivityJPEG.write(to: liveActivityURL, options: .atomic)
            try source.write(to: markerURL, atomically: true, encoding: .utf8)
            WidgetCoverCache.clearLegacyFixedCover()
        } catch {
            #if DEBUG
            print("[WidgetCoverCache] store failed: \(error)")
            #endif
        }
    }
}
