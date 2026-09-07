import SwiftUI

/// Read-only metadata above the physical player; all playback controls live on the machine.
struct ListeningSongCardView: View {
    let room: ListeningRoomCoordinator
    var onShowTracks: (() -> Void)?
    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            Button {
                if room.mechanism.disc != nil {
                    onShowTracks?()
                }
            } label: {
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
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Menu {
                    ForEach(CDPlayerConfiguration.allThemes) { config in
                        Button {
                            room.mechanism.configuration = config
                        } label: {
                            HStack {
                                Text(BSLocalization.text(config.themeName))
                                if room.mechanism.configuration.id == config.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .accessibilityLabel(BSLocalization.text("切换播放器外观"))

                if room.mechanism.disc != nil {
                    Button {
                        onShowTracks?()
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("专辑详情"))
                    .accessibilityIdentifier("listening.discTracks")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("listening.nowPlaying")
        .accessibilityAction(named: BSLocalization.text("下一曲")) { room.skip(1) }
        .accessibilityAction(named: BSLocalization.text("上一曲")) { room.skip(-1) }
    }
}
