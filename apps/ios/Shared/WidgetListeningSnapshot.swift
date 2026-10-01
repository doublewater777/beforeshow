import Foundation

// MARK: - Widget Listening Snapshot
// App 侧把「听模块」状态写成 Codable 快照放进 App Group,widget extension 只读。
// 支持记录当前现场、已装载唱片（合辑或专辑）、当前播放音轨、艺人及播放状态。

struct WidgetCabinetDiscItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var artistName: String?
    var coverImageURL: String?
    var trackCount: Int
    var isLoaded: Bool
}

struct WidgetListeningSnapshot: Codable, Equatable {
    var showID: UUID?
    var showName: String
    var artistName: String?
    var discTitle: String?
    var trackTitle: String?
    var coverImageURL: String?
    var trackCount: Int?
    var isPlaying: Bool
    var cabinetDiscs: [WidgetCabinetDiscItem] = []
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
            && cabinetDiscs == other.cabinetDiscs
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
        let fallbackDiscs = [
            WidgetCabinetDiscItem(id: "compilation-01", title: "热门合辑 01", artistName: nil, coverImageURL: show.coverImageURL, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-02", title: "热门合辑 02", artistName: nil, coverImageURL: show.coverImageURL, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-03", title: "热门合辑 03", artistName: nil, coverImageURL: show.coverImageURL, trackCount: 12, isLoaded: false)
        ]
        return WidgetListeningSnapshot(
            showID: show.showID,
            showName: show.name,
            artistName: nil,
            discTitle: nil,
            trackTitle: nil,
            coverImageURL: show.coverImageURL,
            trackCount: nil,
            isPlaying: false,
            cabinetDiscs: fallbackDiscs,
            generatedAt: show.generatedAt
        )
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
