import SwiftUI

/// One set in the stage matrix.
/// - Heart tap toggles "想看".
/// - Play button directly previews audio.
/// - Card body tap opens the Inspector.
struct TimetableMatrixCard: View {
    let card: TimetableMatrixLayout.Card
    let width: CGFloat
    let avatarURL: URL?
    let artistID: String?
    let isGhost: Bool
    /// Where the now line crosses this card; set only while the set is playing.
    let nowOffset: CGFloat?
    /// The stage's own light, used while the set is playing.
    let stageTint: Color
    let timeZone: TimeZone
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var isPlayingPreview: Bool {
        TimetablePreviewPlayer.shared.isPlaying(performanceID: card.id)
    }

    private var isLoadingPreview: Bool {
        TimetablePreviewPlayer.shared.isLoading(performanceID: card.id)
    }

    private var isToastVisible: Bool {
        TimetablePreviewPlayer.shared.toastPerformanceID == card.id
    }

    private var toastTrackTitle: String? {
        TimetablePreviewPlayer.shared.toastTrackTitle
    }

    private var isEnded: Bool {
        card.status == .ended
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main card button (opens inspector)
            Button(action: onSelect) {
                ZStack(alignment: .topLeading) {
                    background
                }
                .frame(width: width, height: card.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    cardBorder
                }
                .opacity(isEnded ? 0.6 : 1)
            }
            .buttonStyle(TimetablePressStyle())
            .disabled(isGhost)

            // Content with integrated controls
            if !isGhost {
                content
                    .frame(width: width, height: card.height, alignment: .topLeading)
                    .opacity(isEnded ? 0.6 : 1)
            }

            if isToastVisible, let toastTrackTitle {
                previewToastBubble(title: toastTrackTitle)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        )
                    )
                    .zIndex(10)
            }
        }
        .frame(width: width, height: card.height)
        .accessibilityLabel(card.artistName)
        .accessibilityAddTraits(card.isInterested ? .isSelected : [])
        .animation(.easeOut(duration: 0.35), value: isGhost)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: card.isInterested)
        .animation(.snappy, value: isPlayingPreview)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isToastVisible)
    }

    @ViewBuilder
    private var cardBorder: some View {
        if isGhost {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        } else if isPlayingPreview {
            // 正在试听：高亮发光边框，最高优先级，表示正在播放音频
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(TimetableStyle.mine, lineWidth: 2)
                .shadow(color: TimetableStyle.mine.opacity(0.55), radius: 8)
        } else if nowOffset != nil {
            // 正在演出：舞台专属灯光边框
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(stageTint.opacity(0.85), lineWidth: 1.5)
                .shadow(color: stageTint.opacity(0.4), radius: 6)
        } else if card.isInterested {
            if isEnded {
                // 已结束的喜欢：虚线/淡金色边框，表示回顾归档
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(TimetableStyle.mine.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                // 还没开始的喜欢：清晰金色实线边框
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(TimetableStyle.mine.opacity(0.45), lineWidth: 1.2)
            }
        } else {
            // 普通卡片边框
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func previewToastBubble(title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(TimetableStyle.mine)
            Text(BSLocalization.format("正在试听 · %@", title))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .frame(maxWidth: max(width - 8, 40))
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.96))
                .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .offset(x: -4, y: -12)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var background: some View {
        if isGhost {
            Color.clear
        } else {
            let baseColor: Color = {
                if card.isInterested {
                    if isEnded {
                        // 已结束的喜欢：微弱的暗金灰色底，表示已过去
                        return Color(red: 0.125, green: 0.118, blue: 0.108)
                    } else {
                        // 喜欢的现场（未结束）：饱满温润金底
                        return TimetableStyle.cardMine
                    }
                } else {
                    return TimetableStyle.card
                }
            }()

            baseColor
                .overlay(alignment: .top) {
                    // The now line lights the card where it crosses it.
                    if let nowOffset {
                        ZStack {
                            stageTint.opacity(0.12)
                            LinearGradient(
                                colors: [stageTint.opacity(0), stageTint.opacity(0.25), stageTint.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 96)
                            .offset(y: nowOffset - card.height / 2)
                        }
                    }
                }
                .saturation(nowOffset != nil ? TimetableStyle.liveCardBackgroundSaturation : 1)
        }
    }

    private var avatarSize: CGFloat {
        card.height < 52 ? 22 : 28
    }

    private var topPadding: CGFloat {
        card.height < 64 ? 10 : 15
    }

    private var horizontalPadding: CGFloat {
        width < 155 ? 12 : 16
    }

    private var actionToTitleSpacing: CGFloat {
        card.height < 64 ? 6 : 11
    }

    private var titleToMetaSpacing: CGFloat {
        5
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部操作区：左侧头像 + 紧跟播放按钮，右侧固定贴齐爱心，整体垂直居中
            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .center, spacing: 9) {
                    TimetableArtistAvatar(name: card.artistName, url: avatarURL, size: avatarSize)
                        .allowsHitTesting(false)
                    playPreviewButton
                }

                Spacer(minLength: 4)

                heartButton
            }
            .frame(height: max(avatarSize, 28))

            // 艺人名称
            name
                .padding(.top, actionToTitleSpacing)

            // 时间信息
            if card.height >= 56 {
                meta
                    .padding(.top, titleToMetaSpacing)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 8)
    }

    private var heartButton: some View {
        Button(action: onToggle) {
            heartIcon
                .frame(width: 28, height: 28, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(TimetableHeartButtonStyle())
        .accessibilityLabel(BSLocalization.text(card.isInterested ? "取消想看" : "想看"))
    }

    private var playPreviewButton: some View {
        Button {
            TimetablePreviewPlayer.shared.toggle(performanceID: card.id, artistName: card.artistName, artistID: artistID)
        } label: {
            ZStack {
                Circle()
                    .fill(isPlayingPreview ? TimetableStyle.mine.opacity(0.35) : Color.white.opacity(0.14))
                    .frame(width: 22, height: 22)
                if isLoadingPreview {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else if isPlayingPreview {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(TimetableStyle.mine)
                } else {
                    Image(systemName: TimetablePreviewPlayer.shared.failedPerformanceID == card.id ? "arrow.clockwise" : "play.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 0.5)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text(isPlayingPreview ? "暂停试听" : "试听"))
    }

    private var name: some View {
        Text(card.artistName)
            .font(.system(size: 14.5, weight: .heavy))
            .tracking(-0.15)
            .foregroundStyle(isEnded ? Color.white.opacity(0.72) : Color.white)
            .shadow(color: Color.black.opacity(0.4), radius: 1, y: 0.5)
            .lineSpacing(1)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
    }

    private var heartIcon: some View {
        Group {
            if card.isInterested {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isEnded ? TimetableStyle.mine.opacity(0.5) : TimetableStyle.mine)
                    .shadow(color: isEnded ? .clear : TimetableStyle.mine.opacity(0.4), radius: 3)
            } else {
                Image(systemName: "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .contentTransition(.symbolEffect(.replace))
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 4) {
            switch card.status {
            case .soon(let minutes):
                Circle()
                    .strokeBorder(TimetableStyle.now, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                Text(BSLocalization.format("%d 分钟后", minutes))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(TimetableStyle.nowSoft)
            case .live:
                timeText.foregroundStyle(Color.white.opacity(0.95))
            case .ended:
                timeText.foregroundStyle(Color.white.opacity(0.4))
            default:
                timeText.foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .allowsHitTesting(false)
    }

    private var timeText: some View {
        Text(TimetableTimeFormat.range(card.startsAt, card.endsAt, timeZone: timeZone))
            .font(TimetableStyle.mono(11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

struct TimetableHeartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.25 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum TimetableTimeFormat {
    static func time(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func range(_ start: Date, _ end: Date, timeZone: TimeZone) -> String {
        "\(time(start, timeZone: timeZone))–\(time(end, timeZone: timeZone))"
    }
}
