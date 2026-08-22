import SwiftUI
import WidgetKit

// MARK: - Countdown Widget Views
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 与 app 首页同一套精度收束:>1 天天数 hero、<24h 时:分:秒、live 正在现场;
// 秒针用 Text(timerInterval:) 原生跳动,不靠 timeline 高频刷新。

struct CountdownWidgetView: View {
    let entry: CountdownEntry

    @Environment(\.widgetFamily) private var family

    private var presentation: CountdownPresentation {
        CountdownPresentation(entry: entry)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallCountdownView(presentation: presentation)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
        case .systemMedium:
            MediumCountdownView(presentation: presentation, coverImagePath: entry.coverImagePath)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
        case .accessoryInline:
            InlineCountdownView(presentation: presentation)
                .containerBackground(for: .widget) {}
        case .accessoryCircular:
            CircularCountdownView(presentation: presentation)
                .containerBackground(for: .widget) {}
        case .accessoryRectangular:
            RectangularCountdownView(presentation: presentation)
                .containerBackground(for: .widget) {}
        default:
            EmptyView()
        }
    }
}

// MARK: - Presentation
// 视图输入一次性算好;kind/phase 推导复用 Shared 的 CurrentShowTimeState + HomeShowPhase。

struct CountdownPresentation {
    enum Hero: Equatable {
        case far(days: Int)
        case near(start: Date)
        case live(start: Date)
        case ended
        /// 估算结束时间已过、用户尚未确认散场:不说「已落幕」,与首页「待确认」一致。
        case endUnconfirmed
        case inactive(title: String)
        case empty
    }

    let hero: Hero
    let showName: String
    let city: String?
    let venueName: String?
    let startDate: Date?
    let endBoundary: Date?
    let calendar: Calendar
    /// 距开场的秒数(entry 时刻),给圆形进度环用
    let remainingSeconds: Int

    var hasShow: Bool { hero != .empty }

    init(entry: CountdownEntry) {
        guard let snapshot = entry.snapshot else {
            hero = .empty
            showName = ""
            city = nil
            venueName = nil
            startDate = nil
            endBoundary = nil
            calendar = .current
            remainingSeconds = 0
            return
        }

        showName = snapshot.name
        city = snapshot.city
        venueName = snapshot.venueName

        let state = CurrentShowTimeState(timing: snapshot.timing, now: entry.date)
        calendar = snapshot.timing.eventCalendar(fallback: .current)
        startDate = state.effectiveStartTime
        endBoundary = state.endBoundary
        let remaining = state.effectiveStartTime
            .map { max(0, Int($0.timeIntervalSince(entry.date))) } ?? 0
        remainingSeconds = remaining

        switch HomeShowPhase(timeState: state, now: entry.date) {
        case .pre:
            // 与首页一致:按实际剩余秒数分档,不用日历 dayDistance
            // (23:50→次日 00:10 是 20 分钟,不是「1 天」)
            // 用 `>` 阈值:start−24h 的 timeline entry 上 remaining==86400 必须已是 near
            if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: remaining) {
                hero = .far(days: remaining / Int(WidgetTimelinePlanner.dayCountdownThreshold))
            } else if let start = state.effectiveStartTime {
                hero = .near(start: start)
            } else {
                hero = .inactive(title: state.title)
            }
        case .live:
            if let start = state.effectiveStartTime {
                hero = .live(start: start)
            } else {
                hero = .inactive(title: state.title)
            }
        case .ended:
            // 无明确结束时间的演出,start+默认时长 只是估算边界:
            // 用户未确认 endedAt 前不算「已落幕」。dayEnded 是单日循环内部态,仍按已落幕处理。
            if CurrentShowTimeState.isUnconfirmedEstimatedEnd(
                kind: state.kind,
                hasConfirmedEnd: snapshot.timing.endedAt != nil
            ) {
                hero = .endUnconfirmed
            } else {
                hero = .ended
            }
        case .inactive:
            hero = .inactive(title: state.title)
        }
    }

    var nameLine: String {
        guard let city, !city.isEmpty else { return showName }
        return BSLocalization.format("%@ · %@站", showName, city)
    }

    var dateLine: String {
        guard let startDate else { return "" }
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: startDate)
        return String(
            format: BSLocalization.text("%d月%d日 %02d:%02d"),
            components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0
        )
    }

    /// 「今晚」仅当日开场;`<24h` 但跨日只报钟点,避免今晚看明天场仍写今晚。
    var isStartTonight: Bool {
        guard let startDate else { return false }
        return calendar.isDateInToday(startDate)
    }

    var clockText: String {
        guard let startDate else { return "" }
        let components = calendar.dateComponents([.hour, .minute], from: startDate)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    var tonightClockText: String {
        BSLocalization.format("今晚 %@", clockText)
    }

    /// 顶部时期标签只在 Hero 是数字(far/near)时出现;
    /// Hero 已是状态文字(live/ended/inactive)时 kicker 消失,避免同状态说两遍。
    var showsPhaseTag: Bool {
        switch hero {
        case .far, .near:
            return true
        case .live, .ended, .endUnconfirmed, .inactive, .empty:
            return false
        }
    }

    var phaseTag: String {
        switch hero {
        case .far:
            return BSLocalization.text("距离灯亮还有")
        case .near:
            return isStartTonight
                ? BSLocalization.text("今晚开场")
                : BSLocalization.text("即将开场")
        case .live, .ended, .endUnconfirmed, .inactive, .empty:
            return ""
        }
    }
}

// MARK: - 共用元素

private struct LiveDot: View {
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(WidgetTheme.live)
            .frame(width: size, height: size)
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ticket")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text("还没有现场")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
            Text("打开开场前,添加下一场")
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 小号 170×170

private struct SmallCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        if presentation.hasShow {
            VStack(alignment: .leading, spacing: 0) {
                if presentation.showsPhaseTag {
                    Text(presentation.phaseTag)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(WidgetTheme.muted)
                }

                Spacer(minLength: 4)

                heroView

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.nameLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.dateLine)
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
                // 撑满列宽:仅按内容理想宽度布局时,长文案会被错误截断
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyWidgetView()
        }
    }

    @ViewBuilder
    private var heroView: some View {
        switch presentation.hero {
        case .far(let days):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(days)")
                    .font(.system(size: 56, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(WidgetTheme.heroIvory)
                Text("天")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetTheme.muted)
            }
        case .near(let start):
            Text(start, style: .timer)
                .font(.system(size: 33, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.heroWarmGold)
        case .live(let start):
            VStack(alignment: .leading, spacing: 4) {
                Text("正在现场")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.liveTitle)
                Text(start, style: .timer)
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
            }
        case .ended:
            Text("已落幕")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .endUnconfirmed:
            Text("已到预计散场时间")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .inactive(let title):
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .empty:
            EmptyView()
        }
    }
}

// MARK: - 中号 364×170

private struct MediumCountdownView: View {
    let presentation: CountdownPresentation
    let coverImagePath: String?

    var body: some View {
        if presentation.hasShow {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if presentation.showsPhaseTag {
                        Text(presentation.phaseTag)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(WidgetTheme.muted)
                    }

                    Spacer(minLength: 4)

                    heroView

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.nameLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetTheme.foreground)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(venueLine)
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetTheme.dim)
                            .lineLimit(1)
                    }
                    // 撑满列宽:仅按内容理想宽度布局时,长文案会被错误截断
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 文本列吃满剩余宽度,把封面固定到右缘;
                // 否则封面紧跟文本浮动,与右缘的间距随文案长短漂移。
                .frame(maxWidth: .infinity, alignment: .leading)

                coverView
            }
        } else {
            EmptyWidgetView()
        }
    }

    private var venueLine: String {
        guard let venue = presentation.venueName, !venue.isEmpty else {
            return presentation.dateLine
        }
        return "\(presentation.dateLine) · \(venue)"
    }

    @ViewBuilder
    private var heroView: some View {
        switch presentation.hero {
        case .far(let days):
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(days)")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(WidgetTheme.heroIvory)
                    Text("天")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetTheme.muted)
                }
                Spacer(minLength: 0)
            }
        case .near(let start):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(start, style: .timer)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.heroWarmGold)
                    Text("时 : 分 : 秒")
                        .font(.system(size: 9))
                        .foregroundStyle(WidgetTheme.dim)
                }
                Spacer(minLength: 0)
            }
        case .live(let start):
            HStack(spacing: 10) {
                LiveDot(size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在现场")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetTheme.liveTitle)
                    Text(start, style: .timer)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.foreground)
                }
                Spacer(minLength: 0)
            }
        case .ended:
            Text("已落幕")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .endUnconfirmed:
            Text("已到预计散场时间")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .inactive(let title):
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverImagePath, let image = UIImage(contentsOfFile: coverImagePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 108)
                .clipped()
                // 左缘淡出到氛围底，不要涂一层近黑——浅色海报边会被涂成黑条。
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 18)
                        Color.black
                    }
                }
        }
    }
}

// MARK: - 锁屏 inline(单色,平台强制)

private struct InlineCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        switch presentation.hero {
        case .far(let days):
            Text("还有 \(days) 天 · \(presentation.showName)")
        case .near(let start):
            if presentation.isStartTonight {
                Text("\(presentation.tonightClockText) · \(Text(start, style: .timer))")
            } else {
                Text("\(presentation.clockText) · \(Text(start, style: .timer))")
            }
        case .live(let start):
            Text("正在现场 · \(Text(start, style: .timer))")
        case .ended:
            Text("已落幕 · \(presentation.showName)")
        case .endUnconfirmed:
            Text("待确认 · \(presentation.showName)")
        case .inactive(let title):
            Text("\(title) · \(presentation.showName)")
        case .empty:
            Text("开场前 · 还没有现场")
        }
    }
}

// MARK: - 锁屏圆形

private struct CircularCountdownView: View {
    let presentation: CountdownPresentation

    /// 预习期 14 天窗口:环随临近填满,正在现场满环。
    private var progress: Double {
        switch presentation.hero {
        case .live: return 1
        case .ended, .endUnconfirmed, .inactive, .empty: return 0
        default:
            let window: Double = 14 * 86_400
            return 1 - min(max(Double(presentation.remainingSeconds), 0), window) / window
        }
    }

    var body: some View {
        Gauge(value: progress, in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            centerLabel
        }
        .gaugeStyle(.accessoryCircular)
    }

    @ViewBuilder
    private var centerLabel: some View {
        switch presentation.hero {
        case .far(let days):
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 16, weight: .bold))
                Text("天")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        case .near:
            VStack(spacing: 0) {
                Text(LockScreenCountdownCopy.circularNearClock(remainingSeconds: presentation.remainingSeconds))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                if presentation.isStartTonight {
                    Text("今晚")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
            }
        case .live(let start):
            VStack(spacing: 1) {
                Circle().frame(width: 5, height: 5)
                Text(start, style: .timer)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
            }
        case .ended:
            Text("已落幕")
                .font(.system(size: 10, weight: .bold))
        case .endUnconfirmed:
            Text("待确认")
                .font(.system(size: 10, weight: .bold))
        case .inactive(let title):
            Text(title)
                .font(.system(size: 11, weight: .bold))
        case .empty:
            Text("--")
                .font(.system(size: 14, weight: .bold))
        }
    }
}

// MARK: - 锁屏长条

private struct RectangularCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            headline
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Text(presentation.hasShow ? "\(presentation.showName) · \(presentation.dateLine)" : "打开开场前,添加下一场")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headline: some View {
        switch presentation.hero {
        case .far(let days):
            Text("还有 \(days) 天")
        case .near(let start):
            if presentation.isStartTonight {
                Text(presentation.tonightClockText)
            } else {
                Text(start, style: .timer)
            }
        case .live(let start):
            Text("正在现场 · \(Text(start, style: .timer))")
        case .ended:
            Text("已落幕")
        case .endUnconfirmed:
            Text("待确认")
        case .inactive(let title):
            Text(title)
        case .empty:
            Text("还没有现场")
        }
    }
}
