import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Widget Cover Cache
// 封面按来源 URL 哈希落盘;只有来源匹配才返回路径。
// 下载后限制体积并下采样到展示尺寸,避免 Live Activity 因图过大启动失败。
// app(为 Live Activity 准备封面)与 widget provider 共用。

enum WidgetCoverCache {
    /// 中号 widget 展示边长上限(108pt×3≈324px,留余量)。
    private static let maxPixelDimension: CGFloat = 400
    /// Live Activity 封面只有 40×40pt;按 3x 限制到 120px——
    /// Apple 要求 LA 图片不超过展示区域,否则活动可能无法启动。
    private static let liveActivityMaxPixelDimension: CGFloat = 120
    private static let maxDownloadBytes = 2 * 1_024 * 1_024

    /// 与 `source` 匹配的缓存路径;无封面或来源不一致时返回 nil。
    static func cachedCoverPath(matching source: String?) -> String? {
        guard let source,
              let filename = freshCoverFilename(for: source),
              let url = coverFileURL(filename: filename),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url.path
    }

    /// 缓存存在且来源一致时返回文件名,否则 nil(调用方应触发 refresh)。
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

    /// Live Activity 小图规格;同样要求来源匹配。
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

    /// 下载、下采样(两档)并写入 App Group;来源未变时直接返回。`source` 为空则清理固定旧路径兼容项。
    static func refresh(for source: String?) async {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            clearLegacyFixedCover()
            return
        }
        if freshCoverFilename(for: trimmed) != nil,
           freshLiveActivityCoverFilename(for: trimmed) != nil { return }

        guard let remoteURL = URL(string: trimmed),
              let cacheURL = coverFileURL(for: trimmed),
              let liveActivityURL = coverFileURL(filename: liveActivityFilename(for: trimmed)),
              let markerURL = markerFileURL(for: trimmed) else {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                print("[WidgetCoverCache] non-200 for \(trimmed)")
                #endif
                return
            }
            guard data.count <= maxDownloadBytes else {
                #if DEBUG
                print("[WidgetCoverCache] payload too large: \(data.count) bytes")
                #endif
                return
            }
            guard let mime = http.mimeType, mime.hasPrefix("image/") else {
                #if DEBUG
                print("[WidgetCoverCache] unexpected MIME: \(http.mimeType ?? "nil")")
                #endif
                return
            }
            guard let jpeg = downsampledJPEG(from: data, maxPixel: maxPixelDimension),
                  let liveActivityJPEG = downsampledJPEG(from: data, maxPixel: liveActivityMaxPixelDimension) else {
                #if DEBUG
                print("[WidgetCoverCache] downsample failed for \(trimmed)")
                #endif
                return
            }
            try jpeg.write(to: cacheURL, options: .atomic)
            try liveActivityJPEG.write(to: liveActivityURL, options: .atomic)
            try trimmed.write(to: markerURL, atomically: true, encoding: .utf8)
            clearLegacyFixedCover()
            pruneCoversExcept(currentSource: trimmed)
        } catch {
            #if DEBUG
            print("[WidgetCoverCache] refresh failed: \(error)")
            #endif
        }
    }

    // MARK: - Paths

    private static func coverFileURL(for source: String) -> URL? {
        coverFileURL(filename: filename(for: source))
    }

    private static func coverFileURL(filename: String) -> URL? {
        WidgetSnapshotStore.containerURL?
            .appendingPathComponent(filename, isDirectory: false)
    }

    private static func markerFileURL(for source: String) -> URL? {
        coverFileURL(for: source)?.appendingPathExtension("source")
    }

    /// 不可变文件名:URL 哈希,避免换场后仍读到上一场固定路径封面。
    static func filename(for source: String) -> String {
        let digest = stableHash(source.trimmingCharacters(in: .whitespacesAndNewlines))
        return "cover-\(digest).jpg"
    }

    /// Live Activity 小图文件名。
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

    /// 清理旧版固定文件名 `current-show-cover.jpg`,避免失配残留。
    private static func clearLegacyFixedCover() {
        guard let base = WidgetSnapshotStore.containerURL else { return }
        let legacy = base.appendingPathComponent(WidgetSnapshotStore.legacyCoverCacheFilename, isDirectory: false)
        let legacyMarker = legacy.appendingPathExtension("source")
        try? FileManager.default.removeItem(at: legacy)
        try? FileManager.default.removeItem(at: legacyMarker)
    }

    /// 只保留当前来源的封面文件;历史哈希缓存(含对应 marker)随换场清理,避免长期积累。
    private static func pruneCoversExcept(currentSource: String) {
        guard let base = WidgetSnapshotStore.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return
        }
        let keep: Set<String> = [
            filename(for: currentSource),
            liveActivityFilename(for: currentSource),
            filename(for: currentSource) + ".source",
        ]
        for file in files where file.hasPrefix("cover-") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(file, isDirectory: false))
        }
    }

    // MARK: - Image processing

    private static func downsampledJPEG(from data: Data, maxPixel: CGFloat) -> Data? {
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
