import SwiftUI
import WidgetKit

// MARK: - 现场模式阵容
// 信息顺序:① 谁在演(头像 + 大字艺人名)② 谁同时在演 ③ 下一场几点、是谁。
// 计时退到状态行右端小字;剩余交给进度条。

private struct LiveActivityAvatar: View {
    let filename: String?
    let name: String
    let size: CGFloat
    var ring: Color? = nil

    var body: some View {
        Group {
            if let filename,
               let image = WidgetCoverCache.liveActivityImage(filename: filename, filling: CGSize(width: size, height: size)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(WidgetTheme.surfaceRaised)
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if let ring {
                Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.035))
            }
        }
    }
}

struct LiveActivityLineup: View {
    let content: LiveActivityContent
    let lineup: (avatar: String?, stage: String?, also: LiveActivityContent.Also?)
    var heroSize: CGFloat = 64

    private var isExpanded: Bool { heroSize < 64 }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 14) {
            HStack(alignment: .center, spacing: isExpanded ? 12 : 16) {
                hero

                VStack(alignment: .leading, spacing: isExpanded ? 4 : 6) {
                    // 设计稿「现场模式实时活动 · 艺人头像」:状态行(左状态·舞台，右计时)/ 22pt 艺人名 / 同时在演。
                    HStack(spacing: 6) {
                        statusLabel
                        Spacer(minLength: 4)
                        // 右上角:本场起止 / 下一场开演，都用 HH:mm。
                        if let hint = content.cornerHint() {
                            Text(hint)
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(WidgetTheme.muted)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                    Text(content.title)
                        .font(.system(size: isExpanded ? 19 : 22, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let also = lineup.also {
                        HStack(spacing: 6) {
                            LiveActivityAvatar(filename: also.image, name: also.artist, size: isExpanded ? 16 : 18)
                            Text("同时")
                                .foregroundStyle(WidgetTheme.muted)
                            Text(also.artist)
                                .fontWeight(.semibold)
                                .foregroundStyle(WidgetTheme.foreground)
                                .lineLimit(1)
                            if let stage = also.stage {
                                Text(stage)
                                    .foregroundStyle(WidgetTheme.dim)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: isExpanded ? 12 : 13))
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let next = content.next {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
                HStack(spacing: isExpanded ? 6 : 8) {
                    Text(next.time)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.heroWarmGold)
                        .layoutPriority(2)
                    LiveActivityAvatar(filename: next.image, name: next.artist, size: isExpanded ? 18 : 20)
                    Text(next.artist)
                        .fontWeight(.semibold)
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if next.isInterested {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetTheme.accent)
                    }
                    if let stage = next.stage {
                        Text(stage)
                            .foregroundStyle(WidgetTheme.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
        }
    }

    /// 头像外圈即进度:正在演为随本场时间走满的原生红环(系统时间驱动，无需 app 更新);
    /// 等开演为金色细环。
    private var hero: some View {
        let ringSize = heroSize + (isExpanded ? 10 : 12)
        return ZStack {
            if content.mode == .set, let progress = content.progress {
                Circle()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: Self.ringWidth)
                    .frame(width: ringSize, height: ringSize)
                LiveActivityThinRing(progress: progress, size: ringSize)
                    .overlay {
                        LiveActivityAvatar(filename: lineup.avatar, name: content.title, size: heroSize)
                    }
            } else {
                Circle()
                    .strokeBorder(WidgetTheme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                    .frame(width: ringSize, height: ringSize)
                LiveActivityAvatar(filename: lineup.avatar, name: content.title, size: heroSize)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    static let ringWidth: CGFloat = 2

    /// 「〰 正在演出 · 星光舞台」/「下一场 · 主舞台」
    private var statusLabel: some View {
        HStack(spacing: 5) {
            if content.showsWave {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.live)
            }
            Text(lineup.stage.map { "\(content.kicker) · \($0)" } ?? content.kicker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(content.kickerColor)
                .lineLimit(1)
        }
    }
}

/// 系统圆形进度(随时间自走):无需后台唤醒，由系统实时自动驱动走满。
struct LiveActivityThinRing: View {
    let progress: ClosedRange<Date>
    let size: CGFloat

    var body: some View {
        ProgressView(timerInterval: progress, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(WidgetTheme.live)
        .frame(width: size, height: size)
    }
}
