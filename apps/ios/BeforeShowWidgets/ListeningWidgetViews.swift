import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Listening Widget Views
// 设计语言对齐 BeforeShow 听模块:实体 CD 机、封套抽碟(Sleeve + Peeking Disc)、镭射光盘与暗场光晕。
// 支持在小组件表面直接交互播放/切歌(基于 AudioPlaybackIntent)，并保留点按封面一键直跳 App CD 播放机。

struct ListeningWidgetView: View {
    let entry: ListeningEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallListeningView(entry: entry)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
                .widgetURL(URL(string: "beforeshow://listen"))
        case .systemMedium:
            MediumListeningView(entry: entry)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
                .widgetURL(URL(string: "beforeshow://listen"))
        case .accessoryInline:
            InlineListeningView(entry: entry)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "beforeshow://listen"))
        case .accessoryCircular:
            CircularListeningView(entry: entry)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "beforeshow://listen"))
        case .accessoryRectangular:
            RectangularListeningView(entry: entry)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "beforeshow://listen"))
        default:
            EmptyView()
        }
    }
}

// MARK: - 拟物 CD 光盘 (Laser CD Disc)

struct LaserCDDiscView: View {
    let size: CGFloat
    let coverImagePath: String?
    let isPlaying: Bool

    var body: some View {
        ZStack {
            // CD 盘片外圈银灰底色
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.28),
                            Color(white: 0.16),
                            Color(white: 0.32),
                            Color(white: 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // 镭射反光彩虹渐变 (对齐实体 CD 光学色散)
            AngularGradient(
                gradient: Gradient(colors: [
                    .clear,
                    Color(red: 0.95, green: 0.45, blue: 0.65).opacity(0.35),
                    Color(red: 0.45, green: 0.85, blue: 0.95).opacity(0.40),
                    .clear,
                    Color(red: 0.95, green: 0.85, blue: 0.45).opacity(0.35),
                    Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.40),
                    .clear
                ]),
                center: .center
            )
            .clipShape(Circle())
            .frame(width: size, height: size)

            // 同心音轨车纹 (Concentric Vinyl / Disc Grooves)
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.88, height: size * 0.88)
            Circle()
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
                .frame(width: size * 0.76, height: size * 0.76)
            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: size * 0.64, height: size * 0.64)

            // 中心唱片封面标贴 (Center Label)
            centerLabel
                .frame(width: size * 0.46, height: size * 0.46)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))

            // 中心透明固定夹环与中轴小孔 (Center Spindle Hole)
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.16, height: size * 0.16)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let coverImagePath, let uiImage = UIImage(contentsOfFile: coverImagePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image("default_cover")
                .resizable()
                .scaledToFill()
        }
    }
}

// MARK: - 小号小组件 (SystemSmall 170×170)

private struct SmallListeningView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部状态栏
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Image(systemName: "opticaldisc.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text(BSLocalization.text("现场预习"))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .foregroundStyle(WidgetTheme.accent)

                    Spacer(minLength: 0)

                    if isPlaying {
                        HStack(spacing: 2) {
                            Circle().fill(WidgetTheme.heroWarmGold).frame(width: 4, height: 4)
                            Text(BSLocalization.text("播放中"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(WidgetTheme.heroWarmGold)
                        }
                    }
                }

                Spacer(minLength: 4)

                // 中间 CD 盘片与悬浮交互播放按键
                HStack(spacing: 0) {
                    LaserCDDiscView(
                        size: 78,
                        coverImagePath: entry.coverImagePath,
                        isPlaying: isPlaying
                    )

                    Spacer(minLength: 8)

                    // 直接可点击控制播放/暂停的 AudioPlaybackIntent 按键
                    Button(intent: ToggleListeningPlaybackIntent()) {
                        ZStack {
                            Circle()
                                .fill(WidgetTheme.surfaceRaised)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Circle()
                                        .stroke(WidgetTheme.accent.opacity(0.35), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(WidgetTheme.heroWarmGold)
                                .offset(x: isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isPlaying ? "暂停播放" : "开始播放"))
                }
                .padding(.vertical, 2)

                Spacer(minLength: 4)

                // 底部演出与唱片曲目文案
                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ListeningEmptyWidgetView()
        }
    }

    private var titleText: String {
        snapshot?.discTitle ?? snapshot?.showName ?? BSLocalization.text("现场听歌")
    }

    private var subtitleText: String {
        if let track = snapshot?.trackTitle {
            return track
        }
        if let artist = snapshot?.artistName {
            return artist
        }
        return BSLocalization.text("点击开机听歌")
    }
}

// MARK: - 中号小组件 (SystemMedium 364×170)

private struct MediumListeningView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    var body: some View {
        if let snapshot {
            HStack(spacing: 16) {
                // 左侧:封套 + 抽出的镭射光盘 (Sleeve + Peeking Disc)
                sleevePeekingDiscView

                // 右侧:信息与拟物运输栏控制区
                VStack(alignment: .leading, spacing: 0) {
                    // Kicker 胶囊与现场名
                    HStack(spacing: 4) {
                        Text(BSLocalization.text("现场预习 · 听"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(WidgetTheme.muted)

                        Spacer(minLength: 0)

                        if isPlaying {
                            HStack(spacing: 3) {
                                Circle().fill(WidgetTheme.heroWarmGold).frame(width: 5, height: 5)
                                Text(BSLocalization.text("正在播放"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(WidgetTheme.heroWarmGold)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // 现场名
                    Text(snapshot.showName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)

                    // 唱片与艺人 / 曲目
                    Text(mediumSubtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetTheme.muted)
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 8)

                    // 底部拟物运输栏:⏮ 上一首、▶/⏸ 播放暂停、⏭ 下一首
                    HStack(spacing: 12) {
                        Button(intent: PlayPreviousListeningTrackIntent()) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WidgetTheme.foreground)
                                .frame(width: 32, height: 32)
                                .background(WidgetTheme.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("上一首"))

                        Button(intent: ToggleListeningPlaybackIntent()) {
                            HStack(spacing: 6) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .offset(x: isPlaying ? 0 : 1)
                                Text(isPlaying ? BSLocalization.text("暂停") : BSLocalization.text("开机听歌"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(WidgetTheme.background)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                LinearGradient(
                                    colors: [WidgetTheme.heroWarmGold, WidgetTheme.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: WidgetTheme.accent.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(isPlaying ? "暂停播放" : "开始播放"))

                        Button(intent: PlayNextListeningTrackIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WidgetTheme.foreground)
                                .frame(width: 32, height: 32)
                                .background(WidgetTheme.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("下一首"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ListeningEmptyWidgetView()
        }
    }

    private var mediumSubtitleText: String {
        var parts: [String] = []
        if let artist = snapshot?.artistName, !artist.isEmpty {
            parts.append(artist)
        }
        if let track = snapshot?.trackTitle, !track.isEmpty {
            parts.append(track)
        } else if let disc = snapshot?.discTitle, !disc.isEmpty {
            parts.append(disc)
        }
        return parts.isEmpty ? BSLocalization.text("随身 CD 机 · 即刻开播") : parts.joined(separator: " · ")
    }

    private var sleevePeekingDiscView: some View {
        ZStack(alignment: .leading) {
            // 右侧露出一截 84pt 镭射 CD 光盘
            LaserCDDiscView(
                size: 88,
                coverImagePath: entry.coverImagePath,
                isPlaying: isPlaying
            )
            .offset(x: 20)

            // 左侧 90×90 唱片封套卡片
            sleeveCardView
        }
        .frame(width: 110, height: 96)
    }

    private var sleeveCardView: some View {
        Group {
            if let path = entry.coverImagePath, let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 锁定屏幕小组件 (Lock Screen Accessories)

private struct InlineListeningView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    var body: some View {
        if let snapshot {
            Text("\(isPlaying ? "▶" : "🎧") \(snapshot.showName)")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        } else {
            Text("开场前 · 听现场")
        }
    }
}

private struct CircularListeningView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    var body: some View {
        Button(intent: ToggleListeningPlaybackIntent()) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(3)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RectangularListeningView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: isPlaying ? "waveform" : "opticaldisc.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(snapshot.showName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }

                Text(snapshot.trackTitle ?? snapshot.discTitle ?? snapshot.artistName ?? BSLocalization.text("点击开机听歌"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(isPlaying ? BSLocalization.text("正在播放 · 轻点进 CD 机") : BSLocalization.text("轻点直接开播"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.text("现场听歌"))
                    .font(.headline.weight(.semibold))
                Text(BSLocalization.text("添加现场并开始预习"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 空状态视图

private struct ListeningEmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text(BSLocalization.text("还没有现场"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
            Text(BSLocalization.text("打开开场前，添加现场并开始听歌"))
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
