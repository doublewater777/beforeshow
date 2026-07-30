import SwiftUI
import WidgetKit

// MARK: - Countdown Widget Views
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 与 app 首页同一套精度收束:>1 天天数 hero、<24h 时:分:秒、live 已进行;
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
                    LinearGradient(
                        colors: [WidgetTheme.surfaceRaised, WidgetTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        case .systemMedium:
            MediumCountdownView(presentation: presentation, coverImagePath: entry.coverImagePath)
                .containerBackground(for: .widget) {
                    WidgetTheme.surface
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
        case inactive(title: String)
        case empty
    }

    let hero: Hero
    let showName: String
    let city: String?
    let venueName: String?
    let startDate: Date?
    let endBoundary: Date?
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
            remainingSeconds = 0
            return
        }

        showName = snapshot.name
        city = snapshot.city
        venueName = snapshot.venueName

        let state = CurrentShowTimeState(timing: snapshot.timing, now: entry.date)
        startDate = state.effectiveStartTime
        endBoundary = state.endBoundary
        remainingSeconds = state.effectiveStartTime
            .map { max(0, Int($0.timeIntervalSince(entry.date))) } ?? 0

        switch HomeShowPhase(timeState: state, now: entry.date) {
        case .pre:
            if state.dayDistance >= 1 {
                hero = .far(days: state.dayDistance)
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
            hero = .ended
        case .inactive:
            hero = .inactive(title: state.title)
        }
    }

    var nameLine: String {
        guard let city, !city.isEmpty else { return showName }
        return "\(showName) · \(city)站"
    }

    var dateLine: String {
        guard let startDate else { return "" }
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: startDate)
        return String(
            format: "%d月%d日 %02d:%02d",
            components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0
        )
    }
}

// MARK: - 共用元素

private struct KickerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(WidgetTheme.muted)
    }
}

private struct CountdownBadge: View {
    var body: some View {
        Text("COUNTDOWN")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(WidgetTheme.accent)
    }
}

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
                HStack {
                    KickerLabel(text: kickerText)
                    Spacer(minLength: 0)
                    if case .live = presentation.hero {
                        LiveDot()
                    } else {
                        CountdownBadge()
                    }
                }

                Spacer(minLength: 0)

                heroView

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.nameLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                    Text(presentation.dateLine)
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
            }
        } else {
            EmptyWidgetView()
        }
    }

    private var kickerText: String {
        switch presentation.hero {
        case .near: return "今晚开场"
        case .live: return "演出进行中"
        default: return "距离灯亮还有"
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
                    .foregroundStyle(WidgetTheme.accent)
                Text("天")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetTheme.muted)
            }
        case .near(let start):
            Text(start, style: .timer)
                .font(.system(size: 33, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.foreground)
        case .live(let start):
            VStack(alignment: .leading, spacing: 3) {
                Text("灯光已亮")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.liveTitle)
                Text(start, style: .timer)
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
                Text("已进行")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.dim)
            }
        case .ended:
            Text("已落幕")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
        case .inactive(let title):
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
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
                    HStack {
                        KickerLabel(text: kickerText)
                        Spacer(minLength: 0)
                        if case .live = presentation.hero {
                            Text("ON STAGE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(WidgetTheme.liveTitle)
                        } else {
                            CountdownBadge()
                        }
                    }

                    Spacer(minLength: 0)

                    heroView

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.nameLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetTheme.foreground)
                            .lineLimit(1)
                        Text(venueLine)
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetTheme.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)

                coverView
            }
        } else {
            EmptyWidgetView()
        }
    }

    private var kickerText: String {
        switch presentation.hero {
        case .live: return "演出进行中"
        default: return "距离灯亮还有"
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
                        .foregroundStyle(WidgetTheme.accent)
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
                        .foregroundStyle(WidgetTheme.foreground)
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
                    Text("灯光已亮 · 开场中")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetTheme.liveTitle)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(start, style: .timer)
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WidgetTheme.foreground)
                        Text("已进行")
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetTheme.dim)
                    }
                }
                Spacer(minLength: 0)
            }
        case .ended:
            Text("谢幕了 · 回味还在")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
        case .inactive(let title):
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
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
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [WidgetTheme.surface, WidgetTheme.surface.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 44)
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
            Text("\(days) 天后灯亮 · \(presentation.showName)")
        case .near(let start):
            Text("今晚灯亮 · \(Text(start, style: .timer))")
        case .live(let start):
            Text("开场中 · 已进行 \(Text(start, style: .timer))")
        case .ended:
            Text("已落幕 · \(presentation.showName)")
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

    /// 预习期 14 天窗口:环随临近填满,开场中满环。
    private var progress: Double {
        switch presentation.hero {
        case .live: return 1
        case .ended, .inactive, .empty: return 0
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
            VStack(spacing: 0) {
                Text(start, style: .timer)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                Text("后灯亮")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
        case .live(let start):
            VStack(spacing: 1) {
                Circle().frame(width: 5, height: 5)
                Text(start, style: .timer)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
            }
        case .ended:
            Text("落幕")
                .font(.system(size: 11, weight: .bold))
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
            Text("距灯亮还有 \(days) 天")
        case .near(let start):
            Text("距灯亮 \(Text(start, style: .timer))")
        case .live(let start):
            Text("LIVE · 已进行 \(Text(start, style: .timer))")
        case .ended:
            Text("已落幕 · 回味还在")
        case .inactive(let title):
            Text(title)
        case .empty:
            Text("还没有现场")
        }
    }
}
