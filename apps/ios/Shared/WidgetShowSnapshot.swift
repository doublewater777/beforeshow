import Foundation

// MARK: - Widget Snapshot
// App 侧把「当前现场」写成 Codable 快照放进 App Group,widget extension 只读。
// 不共享 SwiftData store:widget 需要的只是渲染输入,快照是最小契约。

struct WidgetShowSnapshot: Codable, Equatable {
    var showID: UUID
    var name: String
    var city: String?
    var venueName: String?
    var coverImageURL: String?
    var timing: ShowTimingFields
    var generatedAt: Date
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.doublewaterapps.beforeshow"

    private static let snapshotFilename = "current-show.json"
    /// 封面缓存:provider 下载后写这里,视图直接读本地文件。
    static let coverCacheFilename = "current-show-cover.jpg"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static var coverCacheURL: URL? {
        containerURL?.appendingPathComponent(coverCacheFilename, isDirectory: false)
    }

    static func read() -> WidgetShowSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetShowSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetShowSnapshot?) {
        guard let url = snapshotURL else { return }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
