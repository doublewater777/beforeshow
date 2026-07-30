import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Widget Cover Cache
// 封面按来源 URL 哈希落盘;只有来源匹配才返回路径。
// 下载后限制体积并下采样到展示尺寸,避免 Live Activity 因图过大启动失败。
// app(为 Live Activity 准备封面)与 widget provider 共用。

enum WidgetCoverCache {
    /// Live Activity / 中号 widget 展示边长上限(pt×3≈px);原图过大 Activity 可能无法启动。
    private static let maxPixelDimension: CGFloat = 400
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
              let cacheURL = coverFileURL(for: trimmed),
              let markerURL = markerFileURL(for: trimmed),
              FileManager.default.fileExists(atPath: cacheURL.path),
              let cached = try? String(contentsOf: markerURL, encoding: .utf8),
              cached == trimmed else {
            return nil
        }
        return cacheURL.lastPathComponent
    }

    /// 下载、下采样并写入 App Group;来源未变时直接返回。`source` 为空则清理固定旧路径兼容项。
    static func refresh(for source: String?) async {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            clearLegacyFixedCover()
            return
        }
        if freshCoverFilename(for: trimmed) != nil { return }

        guard let remoteURL = URL(string: trimmed),
              let cacheURL = coverFileURL(for: trimmed),
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
            guard let jpeg = downsampledJPEG(from: data, maxPixel: maxPixelDimension) else {
                #if DEBUG
                print("[WidgetCoverCache] downsample failed for \(trimmed)")
                #endif
                return
            }
            try jpeg.write(to: cacheURL, options: .atomic)
            try trimmed.write(to: markerURL, atomically: true, encoding: .utf8)
            clearLegacyFixedCover()
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
