import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Widget Cover Cache
// 封面按来源 URL 哈希落盘;只有来源匹配才返回路径。
// 下载后限制体积并下采样到展示尺寸,避免 Live Activity 因图过大启动失败。
// app(为 Live Activity 准备封面)与 widget provider 共用。
//
// 并发:refresh 经 actor 串行;旧下载在 await 后若已被更新请求取代则丢弃写盘。
// 不在 refresh 内 prune——旧下载后至 prune 会删掉新场封面;清理由调用方在
// 确认当前 source 后显式调用 pruneCovers(except:)。

enum WidgetCoverCache {
    /// 中号 widget 展示边长上限(108pt×3≈324px,留余量)。
    fileprivate static let maxPixelDimension: CGFloat = 400
    /// Live Activity 封面只有 40×40pt;按 3x 限制到 120px——
    /// Apple 要求 LA 图片不超过展示区域,否则活动可能无法启动。
    fileprivate static let liveActivityMaxPixelDimension: CGFloat = 120
    fileprivate static let maxDownloadBytes = 2 * 1_024 * 1_024

    /// 串行化写盘 / 下载完成检查,避免 reentrancy 下旧 refresh 覆盖新场。
    private static let mutator = CoverCacheMutator()

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
    /// 不 prune 历史封面——调用方在确认当前场后调用 `pruneCovers(except:)`。
    static func refresh(for source: String?) async {
        await mutator.refresh(for: source)
    }

    /// 只保留当前来源的封面文件;无来源时清理全部哈希封面。
    /// 由 app 在同步当前现场后调用,避免 refresh 内后至 prune。
    static func pruneCovers(except currentSource: String?) {
        let trimmed = currentSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            clearHashedCovers()
            clearLegacyFixedCover()
            return
        }
        pruneCoversExcept(currentSource: trimmed)
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
    fileprivate static func clearLegacyFixedCover() {
        guard let base = WidgetSnapshotStore.containerURL else { return }
        let legacy = base.appendingPathComponent(WidgetSnapshotStore.legacyCoverCacheFilename, isDirectory: false)
        let legacyMarker = legacy.appendingPathExtension("source")
        try? FileManager.default.removeItem(at: legacy)
        try? FileManager.default.removeItem(at: legacyMarker)
    }

    /// 无当前封面来源时删除所有哈希缓存及 marker,避免切换到无封面现场后永久残留。
    private static func clearHashedCovers() {
        guard let base = WidgetSnapshotStore.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return
        }
        for file in files where file.hasPrefix("cover-") {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(file, isDirectory: false))
        }
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

// MARK: - Serial mutator

/// 单飞 refresh:generation 在 await 前后校验,旧下载完成后不再写盘。
private actor CoverCacheMutator {
    private var generation: UInt64 = 0

    func refresh(for source: String?) async {
        generation &+= 1
        let ticket = generation

        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            guard ticket == generation else { return }
            WidgetCoverCache.clearLegacyFixedCover()
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
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            // 新下载期间又来了更新的 refresh → 丢弃本结果,不写不删
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
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
            guard fileSize > 0, fileSize <= WidgetCoverCache.maxDownloadBytes else {
                #if DEBUG
                print("[WidgetCoverCache] payload too large: \(fileSize) bytes")
                #endif
                return
            }
            let data = try Data(contentsOf: tempURL)
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
            // 故意不 prune:旧 ticket 后至时若 prune 会删掉新场封面
        } catch {
            #if DEBUG
            print("[WidgetCoverCache] refresh failed: \(error)")
            #endif
        }
    }
}
