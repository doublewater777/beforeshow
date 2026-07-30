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

    /// 内容级相等(忽略 generatedAt):generatedAt 每次同步都变,
    /// 用它去重会让「快照没变就不 reload」失效。
    func isContentEqual(to other: WidgetShowSnapshot) -> Bool {
        showID == other.showID
            && name == other.name
            && city == other.city
            && venueName == other.venueName
            && coverImageURL == other.coverImageURL
            && timing == other.timing
    }
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.doublewaterapps.beforeshow"

    private static let snapshotFilename = "current-show.json"
    /// 旧版固定封面路径(仅用于清理);新缓存按 URL 哈希命名,见 WidgetCoverCache。
    static let legacyCoverCacheFilename = "current-show-cover.jpg"

    #if DEBUG
    /// 测试注入:指向临时目录,避免单测读写开发机真实 App Group 快照。
    /// 只在 DEBUG 存在,生产 target 不暴露全局可变状态。
    nonisolated(unsafe) static var overrideContainerURL: URL?
    #endif

    static var containerURL: URL? {
        #if DEBUG
        if let overrideContainerURL { return overrideContainerURL }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static func read() -> WidgetShowSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetShowSnapshot.self, from: data)
        } catch {
            #if DEBUG
            print("[WidgetSnapshotStore] decode failed: \(error)")
            #endif
            return nil
        }
    }

    static func write(_ snapshot: WidgetShowSnapshot?) {
        guard let url = snapshotURL else {
            #if DEBUG
            print("[WidgetSnapshotStore] missing App Group container")
            #endif
            return
        }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[WidgetSnapshotStore] write failed: \(error)")
            #endif
        }
    }
}
