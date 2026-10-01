import Foundation

// MARK: - Widget Listening Snapshot
// App 侧把「听模块」状态写成 Codable 快照放进 App Group,widget extension 只读。

struct WidgetListeningSnapshot: Codable, Equatable {
    var showID: UUID?
    var showName: String
    var artistName: String?
    var discTitle: String?
    var trackTitle: String?
    var coverImageURL: String?
    var trackCount: Int?
    var isPlaying: Bool
    var generatedAt: Date

    /// 内容级相等(忽略 generatedAt 去重)
    func isContentEqual(to other: WidgetListeningSnapshot) -> Bool {
        showID == other.showID
            && showName == other.showName
            && artistName == other.artistName
            && discTitle == other.discTitle
            && trackTitle == other.trackTitle
            && coverImageURL == other.coverImageURL
            && trackCount == other.trackCount
            && isPlaying == other.isPlaying
    }
}

enum WidgetListeningStore {
    static let snapshotFilename = "listening-state.json"

    static var snapshotURL: URL? {
        WidgetSnapshotStore.containerURL?.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static func read() -> WidgetListeningSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return fallbackFromShowSnapshot()
        }
        do {
            return try JSONDecoder().decode(WidgetListeningSnapshot.self, from: data)
        } catch {
            #if DEBUG
            print("[WidgetListeningStore] decode failed: \(error)")
            #endif
            return fallbackFromShowSnapshot()
        }
    }

    /// 当尚未有独立装载唱片快照时，根据当前现场快照降级生成预习快照
    static func fallbackFromShowSnapshot() -> WidgetListeningSnapshot? {
        guard let show = WidgetSnapshotStore.read() else { return nil }
        return WidgetListeningSnapshot(
            showID: show.showID,
            showName: show.name,
            artistName: nil,
            discTitle: nil,
            trackTitle: nil,
            coverImageURL: nil,
            trackCount: nil,
            isPlaying: false,
            generatedAt: show.generatedAt
        )
    }

    /// 只改播放态；没有快照时不做事。
    static func setPlaying(_ isPlaying: Bool) {
        guard var snapshot = read(), snapshot.isPlaying != isPlaying else { return }
        snapshot.isPlaying = isPlaying
        write(snapshot)
    }

    @discardableResult
    static func write(_ snapshot: WidgetListeningSnapshot?) -> Bool {
        guard let url = snapshotURL else {
            #if DEBUG
            print("[WidgetListeningStore] missing App Group container")
            #endif
            return false
        }
        guard let snapshot else {
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            do {
                try FileManager.default.removeItem(at: url)
                return true
            } catch {
                return false
            }
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[WidgetListeningStore] write failed: \(error)")
            #endif
            return false
        }
    }
}
