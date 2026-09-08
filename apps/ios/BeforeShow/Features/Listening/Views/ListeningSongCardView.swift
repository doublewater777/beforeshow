import SwiftUI

/// Read-only metadata above the physical player; all playback controls live on the machine.
struct ListeningSongCardView: View {
    let room: ListeningRoomCoordinator
    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            HStack(spacing: BSSpacing.compact) {
                ListeningArtwork(url: room.track?.artworkURL ?? room.mechanism.disc?.artworkURL,
                                 title: room.mechanism.disc?.title ?? BSLocalization.text("等待唱片"))
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.track?.title ?? (room.mechanism.disc?.title ?? BSLocalization.text("等待唱片")))
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)
                    if let track = room.track {
                        Text([room.currentAlbumTitle, room.currentTrackArtistName ?? track.artistName]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    } else {
                        Text(BSLocalization.text("从下方挑选一张 CD 放入播放机"))
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.dim)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("listening.nowPlaying")
        .accessibilityAction(named: BSLocalization.text("下一曲")) { room.skip(1) }
        .accessibilityAction(named: BSLocalization.text("上一曲")) { room.skip(-1) }
    }
}
