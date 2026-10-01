import SwiftUI
import WidgetKit

// MARK: - Listening Timeline Entry

struct ListeningEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetListeningSnapshot?
    let coverImagePath: String?
    let ambientColor: WidgetAmbientRGB?

    static let empty = ListeningEntry(
        date: .now,
        snapshot: nil,
        coverImagePath: nil,
        ambientColor: nil
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
                isPlaying: false,
                generatedAt: .now
            ),
            coverImagePath: nil,
            ambientColor: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ListeningEntry) -> Void) {
        WidgetLanguage.applyAppLanguageSelection()
        let snapshot = WidgetListeningStore.read()
        let coverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)
        completion(ListeningEntry(
            date: .now,
            snapshot: snapshot,
            coverImagePath: coverPath,
            ambientColor: ambientColor(from: coverPath)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ListeningEntry>) -> Void) {
        WidgetLanguage.applyAppLanguageSelection()
        let snapshot = WidgetListeningStore.read()
        let coverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)
        let ambient = ambientColor(from: coverPath)

        let entry = ListeningEntry(
            date: .now,
            snapshot: snapshot,
            coverImagePath: coverPath,
            ambientColor: ambient
        )

        // 听模块状态主要由 App 侧操作 / Intent 驱动刷新，通常 30 分钟轮询一次即可
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)

        Task {
            let source = snapshot?.coverImageURL
            await WidgetCoverCache.refresh(for: source)
            let refreshed = WidgetCoverCache.cachedCoverPath(matching: source)
            if refreshed != coverPath {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
        }
    }

    private func ambientColor(from coverPath: String?) -> WidgetAmbientRGB? {
        CoverAmbientColor.uiColor(fromCoverAt: coverPath).flatMap(WidgetAmbientRGB.init)
    }
}

// MARK: - Widgets

struct ListeningWidget: Widget {
    let kind = BeforeShowWidgetKind.homeListening

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListeningTimelineProvider()) { entry in
            ListeningWidgetView(entry: entry)
        }
        .configurationDisplayName("现场听歌")
        .description("快速进入当前现场 CD 播放机，随时熟悉演出曲目。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
        ])
    }
}

struct LockScreenListeningWidget: Widget {
    let kind = BeforeShowWidgetKind.lockScreenListening

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListeningTimelineProvider()) { entry in
            ListeningWidgetView(entry: entry)
        }
        .configurationDisplayName("现场听歌")
        .description("锁屏快速控制听歌与进入 CD 播放机。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
