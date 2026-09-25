import SwiftUI

struct ListeningCabinetGridCell: View {
    let disc: ListeningDisc
    let show: Show?
    let isPlaying: Bool
    let isLoaded: Bool
    let artistName: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                ListeningDiscCover(disc: disc, show: show)
                    .overlay(alignment: .bottomLeading) {
                        if isLoaded {
                            ListeningDiscStatusBadge(isPlaying: isPlaying)
                                .padding(BSSpacing.sm)
                        }
                    }
                Text(disc.title)
                    .font(BSListeningTokens.gridTitle)
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(isLoaded ? BSColor.Stage.accent : BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(BSLocalization.format("%d 首歌曲", disc.tracks.count))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.97))
        .accessibilityLabel("\(disc.title), \(artistName)")
        .accessibilityValue(isPlaying ? BSLocalization.text("正在播放") : "")
        .accessibilityIdentifier("listening.cabinet.disc.\(disc.id)")
    }
}
