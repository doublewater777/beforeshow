import SwiftUI
import WidgetKit

// MARK: - Widget Theme
// 与 app 内 BSColor.Stage 同一组值(DesignSystem.swift);extension 单独编一份,
// 避免把 UIKit 依赖的 DesignSystem 拖进 widget target。

enum WidgetTheme {
    static let background = Color(red: 0.020, green: 0.027, blue: 0.051)
    static let surface = Color(red: 0.051, green: 0.067, blue: 0.106)
    static let surfaceRaised = Color(red: 0.082, green: 0.102, blue: 0.153)
    static let foreground = Color(red: 0.949, green: 0.953, blue: 0.969)
    static let muted = Color(red: 0.576, green: 0.600, blue: 0.667)
    static let dim = Color(red: 0.392, green: 0.420, blue: 0.490)
    static let accent = Color(red: 0.910, green: 0.780, blue: 0.557)
    static let live = Color(red: 1.000, green: 0.420, blue: 0.459)
    static let liveTitle = Color(red: 1.000, green: 0.816, blue: 0.827)
}

// MARK: - Timeline

struct CountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetShowSnapshot?
    /// App Group 容器内的封面缓存路径;nil 时用占位/纯色
    let coverImagePath: String?

    static let empty = CountdownEntry(date: .now, snapshot: nil, coverImagePath: nil)
}

struct CountdownTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        // 固定示例,不读 App Group,避免组件库预览受用户数据/IO 影响
        CountdownEntry(
            date: .now,
            snapshot: WidgetShowSnapshot(
                showID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "夜航西飞",
                city: "上海",
                venueName: "梅赛德斯-奔驰文化中心",
                coverImageURL: nil,
                timing: ShowTimingFields(
                    date: Date().addingTimeInterval(3 * 86_400),
                    startTime: Date().addingTimeInterval(3 * 86_400),
                    endDate: nil,
                    endTime: nil,
                    postponedDate: nil,
                    changeStatus: .scheduled
                ),
                generatedAt: .now
            ),
            coverImagePath: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let coverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)
        completion(CountdownEntry(date: .now, snapshot: snapshot, coverImagePath: coverPath))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        // TimelineProvider 仍是 completion 回调 API;用一次性投递盒建立线程安全边界。
        let delivery = OnceTimelineDelivery(completion)
        Task {
            let timeline = await Self.buildTimeline()
            delivery.deliver(timeline)
        }
    }

    static func buildTimeline(
        now: Date = Date(),
        snapshot: WidgetShowSnapshot? = WidgetSnapshotStore.read()
    ) async -> Timeline<CountdownEntry> {
        if let source = snapshot?.coverImageURL {
            await WidgetCoverCache.refresh(for: source)
        } else {
            await WidgetCoverCache.refresh(for: nil)
        }
        let coverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)

        var startBoundary: Date?
        var endBoundary: Date?
        if let timing = snapshot?.timing {
            let state = CurrentShowTimeState(timing: timing, now: now)
            startBoundary = state.effectiveStartTime
            endBoundary = state.endBoundary
        }

        let plan = WidgetTimelinePlanner.entryDates(
            now: now,
            startBoundary: startBoundary,
            endBoundary: endBoundary
        )
        let entries = plan.dates.map {
            CountdownEntry(date: $0, snapshot: snapshot, coverImagePath: coverPath)
        }
        return Timeline(entries: entries, policy: .after(plan.windowEnd))
    }
}

/// WidgetKit completion 未标 Sendable;锁 + 单次消费避免跨 Task 数据竞争。
private final class OnceTimelineDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Timeline<CountdownEntry>) -> Void)?

    init(_ completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        self.completion = completion
    }

    func deliver(_ timeline: Timeline<CountdownEntry>) {
        lock.lock()
        let handler = completion
        completion = nil
        lock.unlock()
        handler?(timeline)
    }
}

// MARK: - Widget

struct CountdownWidget: Widget {
    let kind = "BeforeShowCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownTimelineProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("开场倒计时")
        .description("最近一场现场,灯亮之前一点点靠近。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
