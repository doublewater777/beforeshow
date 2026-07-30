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
        CountdownEntry(date: .now, snapshot: WidgetSnapshotStore.read(), coverImagePath: WidgetCoverCache.cachedCoverPath())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: .now, snapshot: WidgetSnapshotStore.read(), coverImagePath: WidgetCoverCache.cachedCoverPath()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        // completion 只被调用一次,装盒跨 Task 传递是安全的(Swift 6 sending 检查)
        let completionBox = SendableCompletion(completion)
        Task {
            let snapshot = WidgetSnapshotStore.read()
            if let source = snapshot?.coverImageURL {
                await WidgetCoverCache.refresh(for: source)
            }
            let coverPath = WidgetCoverCache.cachedCoverPath()

            let now = Date()
            var dates: [Date] = [now]
            // 每小时刷新兜底远场天数变化
            for hour in 1...11 {
                if let date = Calendar.current.date(byAdding: .hour, value: hour, to: now) {
                    dates.append(date)
                }
            }
            // 开场 / 谢幕边界必须各有一个条目,phase 才能准点切换
            if let timing = snapshot?.timing {
                let state = CurrentShowTimeState(timing: timing, now: now)
                if let start = state.effectiveStartTime, start > now { dates.append(start) }
                if let end = state.endBoundary, end > now { dates.append(end) }
            }

            let entries = dates
                .sorted()
                .reduce(into: [Date]()) { partial, date in
                    if partial.last.map({ abs($0.timeIntervalSince(date)) > 60 }) ?? true {
                        partial.append(date)
                    }
                }
                .map { CountdownEntry(date: $0, snapshot: snapshot, coverImagePath: coverPath) }

            completionBox.call(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

/// TimelineProvider 的 completion 没有标 Sendable,但它恰好只被调用一次——
/// 装一个 @unchecked Sendable 的盒子过 Swift 6 的 sending 检查。
private struct SendableCompletion: @unchecked Sendable {
    private let completion: (Timeline<CountdownEntry>) -> Void

    init(_ completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        self.completion = completion
    }

    func call(_ timeline: Timeline<CountdownEntry>) {
        completion(timeline)
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
