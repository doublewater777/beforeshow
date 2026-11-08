import SwiftUI
import WidgetKit

// MARK: - Listening Timeline Entry

struct ListeningEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetListeningSnapshot?
    let coverImagePath: String?

    static let empty = ListeningEntry(
        date: .now,
        snapshot: nil,
        coverImagePath: nil
    )
}

// MARK: - Timeline Provider

struct ListeningTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListeningEntry {
        ListeningEntry(
            date: .now,
            snapshot: WidgetListeningSnapshot(
                showID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                showName: "夜航西飞",
                artistName: "回春丹",
                discTitle: "热门合辑 01",
                trackTitle: "艾蜜莉",
                coverImageURL: nil,
                trackCount: 12,
                phase: .idle,
                control: .play,
                hasSession: false,
                generatedAt: .now
            ),
            coverImagePath: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ListeningEntry) -> Void) {
        completion(entry(at: .now, stored: WidgetListeningStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ListeningEntry>) -> Void) {
        let now = Date.now
        let stored = WidgetListeningStore.read()
        var entries = [entry(at: now, stored: stored)]
        // 「今天这张」 turns over at local midnight; the App already chose the next day's disc.
        if let stored, !stored.hasSession, let next = stored.nextDisc, next.startsAt > now {
            entries.append(entry(at: next.startsAt, stored: stored))
        }

        // 听模块状态主要由 App 侧操作 / Intent 驱动刷新，通常 30 分钟轮询一次即可
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))

        Task {
            var changed = false
            for (source, path) in entries.map({ ($0.snapshot?.coverImageURL, $0.coverImagePath) }) {
                await WidgetCoverCache.refresh(for: source)
                changed = changed || WidgetCoverCache.cachedCoverPath(matching: source) != path
            }
            if changed {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
        }
    }

    private func entry(at date: Date, stored: WidgetListeningSnapshot?) -> ListeningEntry {
        let snapshot = stored?.shown(at: date)
        let coverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)
        return ListeningEntry(
            date: date,
            snapshot: snapshot,
            coverImagePath: coverPath
        )
    }
}

// MARK: - Widgets

struct ListeningWidget: Widget {
    let kind = BeforeShowWidgetKind.homeListening

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListeningTimelineProvider()) { entry in
            ListeningWidgetView(entry: entry)
        }
        .configurationDisplayName("听歌")
        .description("每天为当前现场挑一张唱片，轻点就听。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
        ])
    }
}

#if DEBUG
private func listeningPreviewEntry(trackTitle: String?, phase: WidgetListeningPhase, hasDisc: Bool = true) -> ListeningEntry {
    let sounding = phase.showsSoundingChrome
    return ListeningEntry(
        date: .now,
        snapshot: WidgetListeningSnapshot(
            showID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            showName: "喜力®星银®·泡泡岛音乐与艺术节·江浙沪站",
            artistName: hasDisc ? "张悬" : nil,
            discTitle: hasDisc ? "城市" : nil,
            trackTitle: trackTitle,
            coverImageURL: nil,
            trackCount: nil,
            phase: phase,
            control: !hasDisc ? .openListen : sounding || phase == .preparing || phase == .waiting ? .pause : .play,
            hasSession: trackTitle != nil,
            generatedAt: .now
        ),
        coverImagePath: nil
    )
}

#Preview("小号", as: .systemSmall) {
    ListeningWidget()
} timeline: {
    listeningPreviewEntry(trackTitle: nil, phase: .idle)
    listeningPreviewEntry(trackTitle: "宝贝", phase: .paused)
    listeningPreviewEntry(trackTitle: "宝贝", phase: .playing)
    listeningPreviewEntry(trackTitle: nil, phase: .unavailable, hasDisc: false)
    ListeningEntry.empty
}

#Preview("中号", as: .systemMedium) {
    ListeningWidget()
} timeline: {
    listeningPreviewEntry(trackTitle: nil, phase: .idle)
    listeningPreviewEntry(trackTitle: "宝贝", phase: .paused)
    listeningPreviewEntry(trackTitle: "宝贝", phase: .playing)
    listeningPreviewEntry(trackTitle: nil, phase: .unavailable, hasDisc: false)
    ListeningEntry.empty
}
#endif
