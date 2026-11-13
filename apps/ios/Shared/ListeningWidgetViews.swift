import AppIntents
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

// MARK: - App-side Widget Preview Card

struct ListeningWidgetCard: View {
    let entry: ListeningEntry
    let family: WidgetFamily
    var uiImage: UIImage? = nil

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallListeningView(entry: entry, uiImage: uiImage)
            default:
                MediumListeningView(entry: entry, uiImage: uiImage)
            }
        }
        .widgetTile(family: family) {
            if entry.snapshot?.discTitle != nil {
                PosterBackground(coverImagePath: entry.coverImagePath, blurred: family != .systemSmall, uiImage: uiImage)
            } else {
                CoverAmbientBloom(ambient: nil)
            }
        }
    }
}

// MARK: - Listening Widget Views
// 与 App 迷你播放器同一种视觉：海报背景 + 静态方形封面 + 一个播放/暂停键。
// 切歌交给系统正在播放控件。

struct ListeningWidgetView: View {
    let entry: ListeningEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallListeningView(entry: entry)
            default:
                MediumListeningView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if entry.snapshot?.discTitle != nil {
                PosterBackground(coverImagePath: entry.coverImagePath, blurred: family != .systemSmall)
            } else {
                CoverAmbientBloom(ambient: nil)
            }
        }
        .widgetURL(URL(string: "beforeshow://listen"))
    }
}

// MARK: - 文案

private struct WidgetListeningCopy {
    /// 主标题：曲目 > 唱片 > 演出名
    let title: String
    /// 副标题：有曲目/唱片时给艺人；只剩演出名时不再补字
    let subtitle: String?
    /// 顶部一行：没有会话时是「今天这张」，有会话时是演出名；主标题已是演出名时省略
    let context: String?

    init(_ snapshot: WidgetListeningSnapshot) {
        let nowPlaying = [snapshot.trackTitle, snapshot.discTitle].compactMap { $0 }.first { !$0.isEmpty }
        title = nowPlaying ?? snapshot.showName
        subtitle = nowPlaying == nil ? nil : snapshot.artistName.flatMap { $0.isEmpty ? nil : $0 }
        if nowPlaying == nil {
            context = nil
        } else {
            context = snapshot.hasSession ? snapshot.showName : BSLocalization.text("今天这张")
        }
    }
}

// MARK: - 小号：海报铺满

struct SmallListeningView: View {
    let entry: ListeningEntry
    var uiImage: UIImage? = nil

    var body: some View {
        if let snapshot = entry.snapshot {
            let copy = WidgetListeningCopy(snapshot)
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.discTitle == nil {
                    SquareCover(path: nil, size: 34, uiImage: uiImage)
                } else if let context = copy.context {
                    ContextLine(text: context)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    TitleBlock(copy: copy, snapshot: snapshot, titleSize: 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PlayPauseButton(snapshot: snapshot, size: 34)
                }
            }
        } else {
            WidgetListeningEmptyView()
        }
    }
}

// MARK: - 中号：文字列在左、方形封面在右

struct MediumListeningView: View {
    let entry: ListeningEntry
    var uiImage: UIImage? = nil

    private let coverSize: CGFloat = 108

    var body: some View {
        if let snapshot = entry.snapshot {
            let copy = WidgetListeningCopy(snapshot)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if let context = copy.context {
                        ContextLine(text: context)
                    }
                    Spacer(minLength: 4)
                    TitleBlock(copy: copy, snapshot: snapshot, titleSize: 17)
                    Spacer(minLength: 8)
                    PlayPauseButton(snapshot: snapshot, size: 34)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SquareCover(path: snapshot.discTitle == nil ? nil : entry.coverImagePath, size: coverSize, uiImage: uiImage)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2.5)
            }
        } else {
            WidgetListeningEmptyView()
        }
    }
}

// MARK: - 共用部件

private struct ContextLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WidgetTheme.muted)
            .lineLimit(1)
    }
}

private struct TitleBlock: View {
    let copy: WidgetListeningCopy
    let snapshot: WidgetListeningSnapshot
    let titleSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(copy.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(snapshot.phase.showsSoundingChrome ? WidgetTheme.heroWarmGold : WidgetTheme.foreground)
                .lineLimit(2)
            if let subtitle = copy.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// 海报背景：封面铺底，压暗后承载文字。中号再做模糊，让右侧方形封面成为主体。
struct PosterBackground: View {
    let coverImagePath: String?
    let blurred: Bool
    var uiImage: UIImage? = nil

    var body: some View {
        ZStack {
            WidgetTheme.background
            if let image = uiImage ?? coverImagePath.flatMap(UIImage.init(contentsOfFile:)) {
                Image(uiImage: image)
                    .resizable()
                    .bsFullColorWidgetImage()
                    .scaledToFill()
                    .blur(radius: blurred ? 24 : 0)
                    .opacity(blurred ? 0.7 : 1)
            } else {
                WidgetTheme.surfaceRaised
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(blurred ? 0.35 : 0), location: 0.3),
                    .init(color: .black.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// 与迷你播放器的封面一致：静态方形、细描边；封面未就绪时是音符占位。
fileprivate struct SquareCover: View {
    let path: String?
    let size: CGFloat
    var uiImage: UIImage? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size > 60 ? 8 : 6, style: .continuous)
        Group {
            if let image = uiImage ?? path.flatMap(UIImage.init(contentsOfFile:)) {
                Image(uiImage: image)
                    .resizable()
                    .bsFullColorWidgetImage()
                    .scaledToFill()
            } else {
                ZStack {
                    WidgetTheme.surfaceRaised
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(WidgetTheme.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }
}

private struct PlayPauseButton: View {
    let snapshot: WidgetListeningSnapshot
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch snapshot.control {
        case .play:
            controlButton(intent: PlayListeningIntent(), systemName: "play.fill", nudge: true)
        case .pause:
            controlButton(intent: PauseListeningIntent(), systemName: "pause.fill", nudge: false)
        case .openListen:
            Text(BSLocalization.text("打开听"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(1)
        }
    }

    private func controlButton(intent: some AppIntent, systemName: String, nudge: Bool) -> some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(iconColor)
                .offset(x: nudge ? size * 0.03 : 0)
                .frame(width: size, height: size)
                .background(buttonBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Clear / Tinted 会把不透明前景统一着色；如果仍用深色 glyph + 实心圆，
    /// 播放图标可能和圆底落到同一色阶。非 fullColor 下改用 alpha 对比保住可读性。
    private var iconColor: Color {
        renderingMode == .fullColor ? WidgetTheme.background : .primary
    }

    private var buttonBackground: Color {
        renderingMode == .fullColor ? WidgetTheme.foreground : Color.primary.opacity(0.18)
    }
}

struct WidgetListeningEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SquareCover(path: nil, size: 34)
            Spacer(minLength: 0)
            Text(BSLocalization.text("添加一场演出，开始听歌"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
