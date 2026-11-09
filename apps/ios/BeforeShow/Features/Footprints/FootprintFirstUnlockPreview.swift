import SwiftUI

/// 有当前现场、还没有散场过的足迹：先把散场后会拿到的东西摆出来，第一张唱片现在就能听。
struct FootprintFirstUnlockPreview: View {
    let show: Show

    private var record: FootprintNumberSong? { FootprintNumberSongs.song(for: 1) }

    private var starNames: String {
        let names = show.artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? show.name : names.prefix(3).joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let record { recordRow(record) }
            divider
            row(
                icon: "sparkle",
                tint: BSColor.Stage.heroIvory,
                title: BSLocalization.text("星空里的第一颗星"),
                subtitle: starNames
            )
            divider
            row(
                icon: FootprintBadgeFamily.ritual.symbol,
                tint: FootprintRoomPalette.badgeMetals[0],
                title: BSLocalization.text("第一枚徽章"),
                subtitle: BSLocalization.format("写下散场留言，得到「%@」", FootprintBadgeFamily.ritual.title)
            )
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.border))
        .padding(.top, BSSpacing.sm)
    }

    private var divider: some View {
        Rectangle().fill(BSColor.Stage.border).frame(height: 1)
    }

    private func recordRow(_ record: FootprintNumberSong) -> some View {
        let player = FootprintNumberSongPlayer.shared
        let isPlaying = player.isPlaying(record.number)
        return Button {
            Task { await player.toggle(record) }
        } label: {
            HStack(spacing: 12) {
                FootprintNumberDisc(number: record.number, diameter: 36, isPlaying: isPlaying)
                    .frame(width: 36, height: 36)
                labels(
                    title: BSLocalization.format("第 %lld 张数字唱片", record.number),
                    subtitle: "\(record.title) · \(record.artist)"
                )
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(BSPressStyle())
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06), in: Circle())
            labels(title: title, subtitle: subtitle)
        }
        .padding(.vertical, 12)
    }

    private func labels(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
