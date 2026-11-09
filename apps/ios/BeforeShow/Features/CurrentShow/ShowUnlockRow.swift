import SwiftUI

/// 散场后倒计时卡里的解锁：唱片转进来，徽章跟在后面。点了去唱片墙或徽章墙。
struct ShowUnlockRow: View {
    let unlocks: ShowUnlocks
    let onOpenRecords: () -> Void
    let onOpenBadges: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived: Bool

    /// 第一次出现时唱片转进来；之后整个停留期都静止显示。
    init(unlocks: ShowUnlocks, animatesArrival: Bool, onOpenRecords: @escaping () -> Void, onOpenBadges: @escaping () -> Void) {
        self.unlocks = unlocks
        self.onOpenRecords = onOpenRecords
        self.onOpenBadges = onOpenBadges
        _arrived = State(initialValue: !animatesArrival)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let record = unlocks.record {
                Button(action: onOpenRecords) { recordLabel(record) }
                    .buttonStyle(BSPressStyle())
            }
            if !unlocks.badges.isEmpty {
                Button(action: onOpenBadges) { badgesLabel }
                    .buttonStyle(BSPressStyle())
                    .opacity(arrived ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(reduceMotion ? 0 : 0.45), value: arrived)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .sensoryFeedback(.success, trigger: arrived)
        .task { arrived = true }
    }

    private func recordLabel(_ record: FootprintNumberSong) -> some View {
        HStack(spacing: 12) {
            FootprintNumberDisc(number: record.number, diameter: 44, isPlaying: FootprintNumberSongPlayer.shared.isPlaying(record.number))
                .rotationEffect(.degrees(arrived || reduceMotion ? 0 : 200))
                .offset(x: arrived || reduceMotion ? 0 : 60)
                .opacity(arrived ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: arrived)
            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.format("送你一首和 %lld 有关的歌", record.number))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Text("\(record.title) · \(record.artist)")
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .contentShape(Rectangle())
    }

    private var badgesLabel: some View {
        HStack(spacing: 8) {
            ForEach(unlocks.badges.prefix(3)) { badge in
                HStack(spacing: 4) {
                    Image(systemName: badge.family.symbol)
                        .foregroundStyle(FootprintRoomPalette.badgeMetals[badge.tier - 1])
                    Text(badge.family.title)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            if unlocks.badges.count > 3 {
                Text("+\(unlocks.badges.count - 3)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
        .contentShape(Rectangle())
    }
}
