import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Listening Widget Views
// 只做「开机」入口：封面 + 将要播放的内容 + 一个播放键。
// 切歌交给系统正在播放控件。

struct ListeningWidgetView: View {
    let entry: ListeningEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallListeningView(entry: entry)
                    .containerBackground(for: .widget) {
                        if entry.snapshot != nil {
                            PosterBackground(coverImagePath: entry.coverImagePath)
                        } else {
                            CoverAmbientBloom(ambient: entry.ambientColor)
                        }
                    }
            default:
                MediumListeningView(entry: entry)
                    .containerBackground(for: .widget) {
                        CoverAmbientBloom(ambient: entry.ambientColor)
                    }
            }
        }
        .widgetURL(URL(string: "beforeshow://listen"))
    }
}

// MARK: - 文案

private struct ListeningCopy {
    /// 主标题：曲目 > 唱片 > 演出名
    let title: String
    /// 副标题：有曲目/唱片时给艺人；只剩演出名时不再补字
    let subtitle: String?
    /// 中号顶部的演出名；主标题已是演出名时省略
    let context: String?

    init(_ snapshot: WidgetListeningSnapshot) {
        let nowPlaying = [snapshot.trackTitle, snapshot.discTitle].compactMap { $0 }.first { !$0.isEmpty }
        title = nowPlaying ?? snapshot.showName
        subtitle = nowPlaying == nil ? nil : snapshot.artistName.flatMap { $0.isEmpty ? nil : $0 }
        context = nowPlaying == nil ? nil : snapshot.showName
    }
}

// MARK: - 小号：海报铺满

private struct SmallListeningView: View {
    let entry: ListeningEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let copy = ListeningCopy(snapshot)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WidgetTheme.foreground)
                            .lineLimit(2)
                        if let subtitle = copy.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(WidgetTheme.foreground.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlayPauseButton(isPlaying: snapshot.isPlaying, size: 34)
                }
            }
        } else {
            ListeningEmptyView()
        }
    }
}

private struct PosterBackground: View {
    let coverImagePath: String?

    var body: some View {
        ZStack {
            WidgetTheme.background
            CoverImage(path: coverImagePath)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.3),
                    .init(color: .black.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - 中号：与倒计时同构，文字列在左、封面在右

private struct MediumListeningView: View {
    let entry: ListeningEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let copy = ListeningCopy(snapshot)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if let context = copy.context {
                        Text(context)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WidgetTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(copy.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(snapshot.isPlaying ? WidgetTheme.heroWarmGold : WidgetTheme.foreground)
                        .lineLimit(2)
                    if let subtitle = copy.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetTheme.muted)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 8)

                    PlayPauseButton(isPlaying: snapshot.isPlaying, size: 34)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SleeveWithDisc(coverImagePath: entry.coverImagePath, isPlaying: snapshot.isPlaying)
                    .padding(.leading, 12)
            }
        } else {
            ListeningEmptyView()
        }
    }
}

/// 封套；播放中从左侧露出一截 CD。
private struct SleeveWithDisc: View {
    let coverImagePath: String?
    let isPlaying: Bool

    private let sleeveSize: CGFloat = 108
    private let discPeek: CGFloat = 22

    var body: some View {
        ZStack(alignment: .trailing) {
            if isPlaying {
                CDDisc(size: sleeveSize - 6)
                    .padding(.trailing, discPeek + 3)
            }
            CoverImage(path: coverImagePath)
                .frame(width: sleeveSize, height: sleeveSize)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.14), location: 0),
                            .init(color: .white.opacity(0), location: 0.35),
                            .init(color: .black.opacity(0.25), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2.5)
        }
        .frame(width: sleeveSize + (isPlaying ? discPeek : 0), alignment: .trailing)
    }
}

// MARK: - 共用部件

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        Button(intent: ToggleListeningPlaybackIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(WidgetTheme.background)
                .offset(x: isPlaying ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(WidgetTheme.heroWarmGold, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct CoverImage: View {
    let path: String?

    var body: some View {
        if let path, let uiImage = UIImage(contentsOfFile: path) {
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

/// 露出部分只有外圈，所以只画镭射面与音轨。
private struct CDDisc: View {
    let size: CGFloat

    private static let laser = Gradient(colors: [
        Color(red: 0.68, green: 0.72, blue: 0.78),
        Color(red: 0.90, green: 0.93, blue: 0.98),
        WidgetTheme.heroWarmGold.opacity(0.70),
        Color(red: 0.38, green: 0.74, blue: 0.82),
        Color(red: 0.70, green: 0.52, blue: 0.92),
        Color(red: 0.88, green: 0.91, blue: 0.96),
        WidgetTheme.accent.opacity(0.70),
        Color(red: 0.36, green: 0.72, blue: 0.78),
        Color(red: 0.62, green: 0.44, blue: 0.82),
        Color(red: 0.68, green: 0.72, blue: 0.78)
    ])

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.2))
            Circle()
                .fill(AngularGradient(gradient: Self.laser, center: .center, angle: .degrees(75)))
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: size * 0.18)
                .padding(size * 0.12)
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
    }
}

private struct ListeningEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text(BSLocalization.text("添加一场演出，开始听歌"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
