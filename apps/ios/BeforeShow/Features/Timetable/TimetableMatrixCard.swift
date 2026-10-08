import SwiftUI

/// One set in the stage matrix. The whole card toggles "想看".
struct TimetableMatrixCard: View {
    let card: TimetableMatrixLayout.Card
    let width: CGFloat
    let avatarURL: URL?
    let isGhost: Bool
    /// Where the now line crosses this card; set only while the set is playing.
    let nowOffset: CGFloat?
    /// The stage's own light, used while the set is playing.
    let stageTint: Color
    let timeZone: TimeZone
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topLeading) {
                background
                content
                    .opacity(isGhost ? 0 : 1)
            }
            .frame(width: width, height: card.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isGhost {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                } else if nowOffset != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(stageTint.opacity(0.7), lineWidth: 1.2)
                }
            }
            .opacity(card.status == .ended ? 0.4 : 1)
        }
        .buttonStyle(TimetablePressStyle())
        .disabled(isGhost)
        .accessibilityLabel(card.artistName)
        .accessibilityAddTraits(card.isInterested ? .isSelected : [])
        .animation(.easeOut(duration: 0.35), value: isGhost)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: card.isInterested)
    }

    @ViewBuilder
    private var background: some View {
        if isGhost {
            Color.clear
        } else {
            (card.isInterested ? TimetableStyle.cardMine : TimetableStyle.card)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(card.isInterested ? TimetableStyle.mine.opacity(0.16) : Color.white.opacity(0.05))
                        .frame(height: 1)
                }
                .overlay(alignment: .top) {
                    // The now line lights the card where it crosses it.
                    if let nowOffset {
                        ZStack {
                            stageTint.opacity(0.1)
                            LinearGradient(
                                colors: [stageTint.opacity(0), stageTint.opacity(0.24), stageTint.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 96)
                            .offset(y: nowOffset - card.height / 2)
                        }
                    }
                }
        }
    }

    /// Avatar placement follows the room the card has: above the name on tall
    /// cards, beside it on short wide ones, and left out where it would squeeze
    /// the name (narrow lanes with three or more stages, very short sets).
    private enum Layout { case stacked(avatar: CGFloat), inline(avatar: CGFloat), text }

    private var layout: Layout {
        let height = card.height
        if height >= 104 { return .stacked(avatar: 36) }
        if width >= 140 {
            let side = min(32, height - 14)
            return side >= 20 ? .inline(avatar: side) : .text
        }
        return height >= 77 ? .stacked(avatar: 22) : .text
    }

    private var content: some View {
        Group {
            switch layout {
            case .stacked(let side):
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        TimetableArtistAvatar(name: card.artistName, url: avatarURL, size: side)
                        Spacer(minLength: 0)
                        heart
                    }
                    .padding(.bottom, side > 30 ? 7 : 5)
                    name.lineLimit(side > 30 || card.height >= 92 ? 2 : 1)
                    meta.padding(.top, 3)
                }
            case .inline(let side):
                HStack(alignment: .top, spacing: 8) {
                    TimetableArtistAvatar(name: card.artistName, url: avatarURL, size: side)
                    VStack(alignment: .leading, spacing: 3) {
                        name.lineLimit(card.height >= 70 ? 2 : 1)
                        if card.height >= 50 { meta }
                    }
                    Spacer(minLength: 0)
                    heart
                }
            case .text:
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        name.lineLimit(card.height >= 70 ? 2 : 1)
                        if card.height >= 50 { meta }
                    }
                    Spacer(minLength: 0)
                    heart
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, card.height < 34 ? 5 : 7)
    }

    private var name: some View {
        Text(card.artistName)
            .font(.system(size: 15, weight: .bold))
            .tracking(-0.15)
            .foregroundStyle(TimetableStyle.foreground)
            .lineSpacing(1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var heart: some View {
        Image(systemName: card.isInterested ? "heart.fill" : "heart")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(card.isInterested ? TimetableStyle.mine : TimetableStyle.foreground.opacity(0.24))
            .contentTransition(.symbolEffect(.replace))
    }

    @ViewBuilder
    private var meta: some View {
        switch card.status {
        case .soon(let minutes):
            HStack(spacing: 5) {
                Circle()
                    .strokeBorder(TimetableStyle.now, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                Text(BSLocalization.format("%d 分钟后", minutes))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TimetableStyle.nowSoft)
            }
        case .live:
            timeText.foregroundStyle(TimetableStyle.foreground)
        default:
            timeText.foregroundStyle(TimetableStyle.muted)
        }
    }

    private var timeText: some View {
        Text(TimetableTimeFormat.range(card.startsAt, card.endsAt, timeZone: timeZone))
            .font(TimetableStyle.mono(11.5))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
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
