import SwiftUI

/// Records your show count has unlocked, led by the next one still in its sleeve,
/// so every new night is a step towards a song.
struct FootprintNumberShelf: View {
    let showCount: Int

    @State private var controller = FootprintNumberSongPlayer.shared

    private static let diameter: CGFloat = 76

    var body: some View {
        let shelf = FootprintNumberSongs.shelf(showCount: showCount)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("数字唱片"))
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                Text(BSLocalization.format("%lld / %lld 张", shelf.unlocked.count, shelf.total))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    if let next = shelf.next {
                        sealed(next, remaining: shelf.remaining)
                    }
                    ForEach(shelf.unlocked, id: \.number) { song in
                        record(song)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The next record, still in its sleeve: its number shows, its song does not.
    private func sealed(_ song: FootprintNumberSong, remaining: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                // The record peeks out of the sleeve.
                Circle()
                    .fill(FootprintRoomPalette.vinyl)
                    .overlay(Circle().stroke(FootprintRoomPalette.groove, lineWidth: 0.8).padding(10))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .offset(x: 22)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(BSColor.Stage.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    )
                    .overlay {
                        VStack(spacing: 0) {
                            Text("?")
                                .font(.system(size: 30, weight: .black).width(.compressed))
                                .foregroundStyle(BSColor.Stage.accent)
                            Text(String(format: "No. %d", song.number))
                                .font(.system(size: 10, weight: .semibold).width(.condensed))
                                .tracking(1.5)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                    }
                    .frame(width: Self.diameter, height: Self.diameter)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
            }
            .frame(width: Self.diameter + 22, alignment: .leading)
            Text(BSLocalization.format("第 %lld 场", song.number))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BSColor.Stage.accent)
            Text(BSLocalization.format("还差 %lld 场", remaining))
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .frame(width: Self.diameter + 22, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func record(_ song: FootprintNumberSong) -> some View {
        let isPlaying = controller.isPlaying(song.number)
        return Button {
            if !isPlaying { FootprintSoundPlayer.shared.play(.needle) }
            Task { await controller.toggle(song) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                FootprintNumberDisc(number: song.number, diameter: Self.diameter, isPlaying: isPlaying)
                Text(song.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPlaying ? BSColor.Stage.accent : BSColor.Stage.foreground)
                    .lineLimit(1)
                Group {
                    if controller.loadingNumber == song.number {
                        Text(BSLocalization.text("正在准备…"))
                    } else if controller.failedNumber == song.number {
                        Text(BSLocalization.text("暂时无法播放"))
                    } else {
                        Text(song.artist)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.dim)
                .lineLimit(1)
            }
            .frame(width: Self.diameter, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isPlaying) { _, playing in playing }
        .accessibilityLabel(isPlaying
            ? BSLocalization.format("暂停 %@", song.title)
            : BSLocalization.format("试听 %@", song.title))
    }
}
