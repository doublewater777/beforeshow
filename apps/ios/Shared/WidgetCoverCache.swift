import Foundation

// MARK: - Widget Cover Cache
// 封面只下载一次:来源 URL 记录在同名 .source 标记文件里,匹配才复用。
// app(为 Live Activity 准备封面)与 widget provider 共用,避免两处各写一份下载逻辑。

enum WidgetCoverCache {
    /// 缓存文件名(不含路径);Live Activity attributes 里传的就是它。
    static var filename: String {
        WidgetSnapshotStore.coverCacheFilename
    }

    static func cachedCoverPath() -> String? {
        guard let url = WidgetSnapshotStore.coverCacheURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url.path
    }

    /// 缓存存在且来源一致时返回文件名,否则 nil(调用方应触发 refresh)。
    static func freshCoverFilename(for source: String) -> String? {
        guard let cacheURL = WidgetSnapshotStore.coverCacheURL,
              let markerURL = WidgetSnapshotStore.coverCacheURL?.appendingPathExtension("source"),
              FileManager.default.fileExists(atPath: cacheURL.path),
              let cached = try? String(contentsOf: markerURL, encoding: .utf8),
              cached == source else {
            return nil
        }
        return filename
    }

    /// 下载并写入 App Group;来源未变时直接返回。
    static func refresh(for source: String) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let remoteURL = URL(string: trimmed),
              let cacheURL = WidgetSnapshotStore.coverCacheURL,
              let markerURL = WidgetSnapshotStore.coverCacheURL?.appendingPathExtension("source") else {
            return
        }
        if freshCoverFilename(for: trimmed) != nil { return }

        guard let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else {
            return
        }
        try? data.write(to: cacheURL, options: .atomic)
        try? trimmed.write(to: markerURL, atomically: true, encoding: .utf8)
    }
}
