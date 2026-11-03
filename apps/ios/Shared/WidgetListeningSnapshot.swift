import Foundation

// MARK: - Widget Listening Snapshot
// App 侧把「听」模块的会话投影写进 App Group。小组件只读，不自己推算播放状态。

enum WidgetListeningPhase: String, Codable, Equatable {
    case idle
    case preparing
    case waiting
    case playing
    case seeking
    case paused
    case interrupted
    case failed
    case unavailable

    /// Gold title and the peeking CD mean sound is actually coming out.
    var showsSoundingChrome: Bool {
        self == .playing || self == .seeking
    }
}

enum WidgetListeningControl: String, Codable, Equatable {
    case play
    case pause
    case openListen
}

struct WidgetListeningSnapshot: Codable, Equatable {
    var showID: UUID?
    var showName: String
    var artistName: String?
    var discTitle: String?
    var trackTitle: String?
    var coverImageURL: String?
    var trackCount: Int?
    var phase: WidgetListeningPhase
    var control: WidgetListeningControl
    /// A seated or in-flight disc owns the widget. Changing the current show must not replace it.
    var hasSession: Bool
    var generatedAt: Date

    func isContentEqual(to other: WidgetListeningSnapshot) -> Bool {
        showID == other.showID
            && showName == other.showName
            && artistName == other.artistName
            && discTitle == other.discTitle
            && trackTitle == other.trackTitle
            && coverImageURL == other.coverImageURL
            && trackCount == other.trackCount
            && phase == other.phase
            && control == other.control
            && hasSession == other.hasSession
    }

    private enum CodingKeys: String, CodingKey {
        case showID, showName, artistName, discTitle, trackTitle, coverImageURL, trackCount
        case phase, control, hasSession, generatedAt, isPlaying
    }

    init(
        showID: UUID?,
        showName: String,
        artistName: String?,
        discTitle: String?,
        trackTitle: String?,
        coverImageURL: String?,
        trackCount: Int?,
        phase: WidgetListeningPhase,
        control: WidgetListeningControl,
        hasSession: Bool,
        generatedAt: Date
    ) {
        self.showID = showID
        self.showName = showName
        self.artistName = artistName
        self.discTitle = discTitle
        self.trackTitle = trackTitle
        self.coverImageURL = coverImageURL
        self.trackCount = trackCount
        self.phase = phase
        self.control = control
        self.hasSession = hasSession
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showID = try container.decodeIfPresent(UUID.self, forKey: .showID)
        showName = try container.decode(String.self, forKey: .showName)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        discTitle = try container.decodeIfPresent(String.self, forKey: .discTitle)
        trackTitle = try container.decodeIfPresent(String.self, forKey: .trackTitle)
        coverImageURL = try container.decodeIfPresent(String.self, forKey: .coverImageURL)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now

        if let phase = try container.decodeIfPresent(WidgetListeningPhase.self, forKey: .phase) {
            self.phase = phase
            control = try container.decodeIfPresent(WidgetListeningControl.self, forKey: .control) ?? .openListen
            hasSession = try container.decodeIfPresent(Bool.self, forKey: .hasSession) ?? false
        } else if try container.decodeIfPresent(Bool.self, forKey: .isPlaying) == true {
            // Snapshots written before phase/control existed. Treat them as a live session
            // so a later show sync does not wipe audio that may still be running.
            phase = .playing
            control = .pause
            hasSession = true
        } else {
            phase = .unavailable
            control = .openListen
            hasSession = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(showID, forKey: .showID)
        try container.encode(showName, forKey: .showName)
        try container.encodeIfPresent(artistName, forKey: .artistName)
        try container.encodeIfPresent(discTitle, forKey: .discTitle)
        try container.encodeIfPresent(trackTitle, forKey: .trackTitle)
        try container.encodeIfPresent(coverImageURL, forKey: .coverImageURL)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
        try container.encode(phase, forKey: .phase)
        try container.encode(control, forKey: .control)
        try container.encode(hasSession, forKey: .hasSession)
        try container.encode(generatedAt, forKey: .generatedAt)
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

    /// The previous show's session has already ended. Publish this show instead.
    static func publishCurrentShow(showID: UUID, showName: String, generatedAt: Date) {
        if read()?.showID == showID { return }
        guard write(WidgetListeningSnapshot(
            showID: showID,
            showName: showName,
            artistName: nil,
            discTitle: nil,
            trackTitle: nil,
            coverImageURL: nil,
            trackCount: nil,
            phase: .unavailable,
            control: .openListen,
            hasSession: false,
            generatedAt: generatedAt
        )) else { return }
        BeforeShowWidgetKind.reloadAllTimelines()
    }

    /// Names a newly current show without a play button. A seated session stays
    /// until Listen publishes the next snapshot. The same show keeps its disc.
    static func adoptShowChange(showID: UUID?, showName: String?, generatedAt: Date) {
        let current = read()
        if current?.hasSession == true { return }
        guard let showID, let showName else {
            write(nil)
            return
        }
        if current?.showID == showID { return }
        write(WidgetListeningSnapshot(
            showID: showID,
            showName: showName,
            artistName: nil,
            discTitle: nil,
            trackTitle: nil,
            coverImageURL: nil,
            trackCount: nil,
            phase: .unavailable,
            control: .openListen,
            hasSession: false,
            generatedAt: generatedAt
        ))
    }

    /// No listening snapshot yet: name the current show and offer Listen, without a play button.
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
            phase: .unavailable,
            control: .openListen,
            hasSession: false,
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
