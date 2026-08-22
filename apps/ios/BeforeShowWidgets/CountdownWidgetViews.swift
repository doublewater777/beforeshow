import SwiftUI
import WidgetKit

// MARK: - Countdown Widget Views
// App 与普通 widget 共用同一条时间语义:
// >24h 天、1~24h 小时、最后 1h 分秒；开场后回到分钟 / 小时分钟，不做秒表。
// 最后一小时仍用系统 .timer 自驱秒数；live 用系统 .relative 自驱本地化的分钟/小时分钟。

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
    /// 距开场的秒数(entry 时刻),给精度选择与圆形进度环用。
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
        remainingSeconds = state.effectiveStartTime
            .map { max(0, Int($0.timeIntervalSince(entry.date))) } ?? 0

        switch HomeShowPhase(timeState: state, now: entry.date) {
        case .pre:
            if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: remainingSeconds) {
                hero = .far(days: remainingSeconds / Int(WidgetTimelinePlanner.dayCountdownThreshold))
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
        case .far, .near:
            return BSLocalization.text("距离开场")
        case .live, .ended, .endUnconfirmed, .inactive, .empty:
            return ""
        }
    }

    var beforeDisplay: CountdownTimeDisplay {
        CountdownTimePresentationPolicy.beforeStart(remainingSeconds: remainingSeconds)
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
                        .tracking(1.0)
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
            unitHero(value: "\(days)", unit: "天", size: 56, color: WidgetTheme.heroIvory)
        case .near(let start):
            switch presentation.beforeDisplay {
            case .hours(let hours):
                unitHero(value: "\(hours)", unit: "小时", size: 52, color: WidgetTheme.heroWarmGold)
            case .minutesSeconds:
                VStack(alignment: .leading, spacing: 2) {
                    Text(start, style: .timer)
                        .font(.system(size: 32, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.accent)
                    Text("分 : 秒")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WidgetTheme.dim)
                }
            case .days(let days):
                unitHero(value: "\(days)", unit: "天", size: 56, color: WidgetTheme.heroIvory)
            case .elapsedMinutes, .elapsedHoursMinutes:
                EmptyView()
            }
        case .live(let start):
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    LiveDot(size: 7)
                    Text("已开场")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.liveTitle)
                }
                Text(start, style: .relative)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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

    private func unitHero(value: String, unit: String, size: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(BSLocalization.text(unit))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetTheme.muted)
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
                            .tracking(1.0)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            unitHero(value: "\(days)", unit: "天", size: 44, color: WidgetTheme.heroIvory)
        case .near(let start):
            switch presentation.beforeDisplay {
            case .hours(let hours):
                unitHero(value: "\(hours)", unit: "小时", size: 42, color: WidgetTheme.heroWarmGold)
            case .minutesSeconds:
                VStack(alignment: .leading, spacing: 2) {
                    Text(start, style: .timer)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.accent)
                    Text("分 : 秒")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WidgetTheme.dim)
                }
            case .days(let days):
                unitHero(value: "\(days)", unit: "天", size: 44, color: WidgetTheme.heroIvory)
            case .elapsedMinutes, .elapsedHoursMinutes:
                EmptyView()
            }
        case .live(let start):
            HStack(spacing: 10) {
                LiveDot(size: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text("已开场")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.liveTitle)
                    Text(start, style: .relative)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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

    private func unitHero(value: String, unit: String, size: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(BSLocalization.text(unit))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.muted)
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
            switch presentation.beforeDisplay {
            case .hours(let hours):
                Text("距离开场 · \(hours) 小时")
            case .minutesSeconds:
                Text("距离开场 · \(Text(start, style: .timer))")
            default:
                Text("距离开场 · \(presentation.showName)")
            }
        case .live(let start):
            Text("已开场 · \(Text(start, style: .relative))")
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
        case .near(let start):
            switch presentation.beforeDisplay {
            case .hours(let hours):
                VStack(spacing: 0) {
                    Text("\(hours)")
                        .font(.system(size: 16, weight: .bold))
                    Text("小时")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
            case .minutesSeconds:
                VStack(spacing: 0) {
                    Text(start, style: .timer)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                    Text("分秒")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
            default:
                Text("--")
            }
        case .live(let start):
            VStack(spacing: 1) {
                LiveDot(size: 5)
                Text(start, style: .relative)
                    .font(.system(size: 8.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("已开场")
                    .font(.system(size: 6.5))
                    .foregroundStyle(.secondary)
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
            Text("距离开场 · \(days) 天")
        case .near(let start):
            switch presentation.beforeDisplay {
            case .hours(let hours):
                Text("距离开场 · \(hours) 小时")
            case .minutesSeconds:
                Text("距离开场 · \(Text(start, style: .timer))")
            default:
                Text("距离开场")
            }
        case .live(let start):
            Text("已开场 · \(Text(start, style: .relative))")
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
