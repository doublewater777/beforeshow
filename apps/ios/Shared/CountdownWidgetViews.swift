import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct CountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetShowSnapshot?
    /// App Group 容器内的封面缓存路径;nil 时用占位/纯色
    let coverImagePath: String?
    let ambientColor: WidgetAmbientRGB?

    static let empty = CountdownEntry(
        date: .now,
        snapshot: nil,
        coverImagePath: nil,
        ambientColor: nil
    )
}

// MARK: - App-side Widget Preview Card

struct CountdownWidgetCard: View {
    let presentation: CountdownPresentation
    let family: WidgetFamily
    let coverImagePath: String?
    let ambientColor: WidgetAmbientRGB?
    let uiImage: UIImage?

    init(entry: CountdownEntry, family: WidgetFamily) {
        self.presentation = CountdownPresentation(entry: entry)
        self.family = family
        self.coverImagePath = entry.coverImagePath
        self.ambientColor = entry.ambientColor
        self.uiImage = nil
    }

    init(presentation: CountdownPresentation, family: WidgetFamily, coverImagePath: String? = nil, ambientColor: WidgetAmbientRGB? = nil, uiImage: UIImage? = nil) {
        self.presentation = presentation
        self.family = family
        self.coverImagePath = coverImagePath
        self.ambientColor = ambientColor
        self.uiImage = uiImage
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if let phase = presentation.festivalPhase {
                    FestivalSmallView(phase: phase, showName: presentation.showName)
                        .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    SmallCountdownView(presentation: presentation)
                }
            case .systemMedium:
                if let phase = presentation.festivalPhase {
                    FestivalMediumView(phase: phase, showName: presentation.showName) {
                        WidgetCoverImage(path: coverImagePath, uiImage: uiImage)
                    }
                    .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    MediumCountdownView(presentation: presentation, coverImagePath: coverImagePath, uiImage: uiImage)
                }
            default:
                EmptyView()
            }
        }
        .widgetTile(family: family) {
            WidgetPhaseBloom(tone: presentation.bloomTone, ambient: ambientColor)
        }
    }
}

// MARK: - Countdown Widget Views
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 与 app 首页同一套精度收束:>24h 自然日 hero、≤24h 时:分:秒、live 正在现场;
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
            Group {
                if let phase = presentation.festivalPhase {
                    FestivalSmallView(phase: phase, showName: presentation.showName)
                        .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    SmallCountdownView(presentation: presentation)
                }
            }
                .containerBackground(for: .widget) {
                    WidgetPhaseBloom(tone: presentation.bloomTone, ambient: entry.ambientColor)
                }
        case .systemMedium:
            Group {
                if let phase = presentation.festivalPhase {
                    FestivalMediumView(phase: phase, showName: presentation.showName) {
                        WidgetCoverImage(path: entry.coverImagePath)
                    }
                    .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    MediumCountdownView(presentation: presentation, coverImagePath: entry.coverImagePath)
                }
            }
                .containerBackground(for: .widget) {
                    WidgetPhaseBloom(tone: presentation.bloomTone, ambient: entry.ambientColor)
                }
        case .accessoryInline:
            Group {
                if let phase = presentation.festivalPhase {
                    FestivalInlineView(phase: phase)
                        .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    InlineCountdownView(presentation: presentation)
                }
            }
                .containerBackground(for: .widget) {}
        case .accessoryCircular:
            Group {
                if let phase = presentation.festivalPhase {
                    FestivalCircularView(phase: phase)
                        .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    CircularCountdownView(presentation: presentation)
                }
            }
                .containerBackground(for: .widget) {}
        case .accessoryRectangular:
            Group {
                if let phase = presentation.festivalPhase {
                    FestivalRectangularView(phase: phase, showName: presentation.showName)
                        .environment(\.timeZone, presentation.calendar.timeZone)
                } else {
                    RectangularCountdownView(presentation: presentation)
                }
            }
                .containerBackground(for: .widget) {}
        default:
            EmptyView()
        }
    }
}

// MARK: - 共用元素

fileprivate struct LiveDot: View {
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(WidgetTheme.live)
            .frame(width: size, height: size)
    }
}

/// 左上角阶段色 + 右下角封面色的双光晕;无封面时右下退回夜空蓝。
struct WidgetPhaseBloom: View {
    enum Tone {
        case neutral, live, gold, night
    }

    let tone: Tone
    let ambient: WidgetAmbientRGB?

    private static let skyBlue = Color(red: 0.25, green: 0.43, blue: 0.63)

    private var lead: (Color, Double) {
        switch tone {
        case .neutral: (Self.skyBlue, 0.38)
        case .live: (WidgetTheme.live, 0.30)
        case .gold: (WidgetTheme.accent, 0.22)
        case .night: (Color(red: 0.51, green: 0.63, blue: 0.92), 0.30)
        }
    }

    var body: some View {
        ZStack {
            WidgetTheme.background
            RadialGradient(
                colors: [lead.0.opacity(lead.1), lead.0.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 180
            )
            RadialGradient(
                colors: [(ambient?.color ?? Self.skyBlue).opacity(0.28), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 160
            )
        }
    }
}

/// 「● 正在现场」状态标签，与音乐节版式同一写法。
struct LiveTag: View {
    var body: some View {
        HStack(spacing: 6) {
            LiveDot()
            Text("正在现场")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WidgetTheme.liveTitle)
        }
    }
}

fileprivate struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ticket")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text("还没有现场")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
            Text("打开开场前，添加下一场")
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func widgetCountdownRange(to start: Date, now: Date = .now) -> ClosedRange<Date> {
    if now < start { return now...start }
    return start...start
}

/// 倒计时时间文本展示。
/// 统一采用能完整容纳 8 位「HH:MM:SS」的稳定字号（~0.8x），
/// 避免在 10 小时分界点时因 Text(timerInterval:) 内部走字而外层视图未重新求值导致字号跳变。
fileprivate func widgetCountdownText(to start: Date, fontSize: CGFloat, color: Color, now: Date = .now) -> some View {
    Text(timerInterval: widgetCountdownRange(to: start, now: now), countsDown: true)
        .font(.system(size: fontSize * 0.82, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(color)
}

// MARK: - 小号 170×170

struct SmallCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        if presentation.hasShow {
            VStack(alignment: .leading, spacing: 0) {
                if presentation.showsPhaseTag {
                    Text(presentation.phaseTag)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(WidgetTheme.muted)
                } else if case .live = presentation.hero {
                    LiveTag()
                }

                Spacer(minLength: 4)

                heroView

                Spacer(minLength: 8)

                if case .near = presentation.hero, let pick = presentation.festival?.firstPick {
                    FestivalNextLine(performance: pick)
                        .padding(.bottom, 4)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.showName)
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
                Text(BSLocalization.format("天（按天数）", days))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetTheme.muted)
            }
        case .near(let start):
            widgetCountdownText(to: start, fontSize: 33, color: WidgetTheme.heroWarmGold)
        case .live(let start):
            VStack(alignment: .leading, spacing: 4) {
                Text(start, style: .timer)
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
                Text("已开场")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.dim)
            }
        case .ended:
            Text(presentation.endedTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .endUnconfirmed:
            Text("散场待确认")
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

struct MediumCountdownView: View {
    let presentation: CountdownPresentation
    let coverImagePath: String?
    var uiImage: UIImage? = nil

    var body: some View {
        if presentation.hasShow {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if presentation.showsPhaseTag {
                        Text(presentation.phaseTag)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(WidgetTheme.muted)
                    } else if case .live = presentation.hero {
                        LiveTag()
                    }

                    Spacer(minLength: 4)

                    heroView

                    Spacer(minLength: 8)

                    if case .near = presentation.hero, let pick = presentation.festival?.firstPick {
                        FestivalNextLine(performance: pick, showsStage: true)
                            .padding(.bottom, 4)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.showName)
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
                    .padding(.leading, 12)
            }
        } else {
            EmptyWidgetView()
        }
    }

    private var venueLine: String {
        presentation.identity.dateVenueLine(dateLine: presentation.dateLine)
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
                    Text(BSLocalization.format("天（按天数）", days))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetTheme.muted)
                }
                Spacer(minLength: 0)
            }
        case .near(let start):
            HStack {
                widgetCountdownText(to: start, fontSize: 34, color: WidgetTheme.heroWarmGold)
                Spacer(minLength: 0)
            }
        case .live(let start):
            VStack(alignment: .leading, spacing: 4) {
                Text(start, style: .timer)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
                Text("已开场")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.dim)
            }
        case .ended:
            Text(presentation.endedTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .lineLimit(2)
        case .endUnconfirmed:
            Text("散场待确认")
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

    private var coverView: some View {
        WidgetCoverImage(path: coverImagePath, uiImage: uiImage)
    }
}

/// 中号右侧 3:4 封面；无封面用 default_cover。
struct WidgetCoverImage: View {
    let path: String?
    var uiImage: UIImage? = nil

    private var image: Image {
        if let uiImage { return Image(uiImage: uiImage) }
        if let path, let image = UIImage(contentsOfFile: path) { return Image(uiImage: image) }
        return Image("default_cover")
    }

    var body: some View {
        image
        .resizable()
        .bsFullColorWidgetImage()
        .scaledToFill()
        .frame(width: WidgetTheme.mediumCoverSize.width, height: WidgetTheme.mediumCoverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: WidgetTheme.widgetCoverCornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
