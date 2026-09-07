import SwiftUI

struct ListeningLibraryView: View {
    @Bindable var room: ListeningRoomCoordinator
    let artist: ListeningArtistPresentation
    let returnToPlayer: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xl) {
            if !artist.top.isEmpty { songs(artist.top, title: "热门") }
            songs(artist.all, title: "全部")
            if !artist.albums.isEmpty { albums }
        }
    }

    private func songs(_ tracks: [ListeningDiscTrack], title: String) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                Text(BSLocalization.text(title)).font(.title3.bold())
                Spacer()
                Text(String(format: "%02d", tracks.count)).font(.caption.monospacedDigit()).foregroundStyle(BSColor.Stage.dim)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    song(track, number: index + 1)
                }
            }
            .background(BSColor.Stage.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
        }
    }

    private func song(_ track: ListeningDiscTrack, number: Int) -> some View {
        let isCurrent = room.track?.id == track.id
        return HStack(spacing: BSSpacing.sm) {
            ZStack {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BSColor.Stage.accent)
                } else {
                    Text(String(format: "%02d", number)).font(.caption.monospacedDigit()).foregroundStyle(BSColor.Stage.dim)
                }
            }
            .frame(width: 28)

            Button { room.playLibrarySong(track, artistID: artist.id); returnToPlayer() } label: {
                HStack(spacing: BSSpacing.sm) {
                    ListeningArtwork(url: track.artworkURL, title: track.title)
                        .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(track.title).font(.subheadline.weight(.medium))
                            .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.foreground).lineLimit(1)
                        Text(track.artistName).font(.caption).foregroundStyle(BSColor.Stage.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, BSSpacing.sm).padding(.vertical, BSSpacing.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border).frame(height: 1).padding(.leading, 40) }
        .accessibilityElement(children: .contain)
    }

    private func albumTrackRow(_ track: ListeningDiscTrack, number: Int, album: ListeningDisc) -> some View {
        let isCurrent = room.track?.id == track.id
        return HStack(spacing: BSSpacing.sm) {
            ZStack {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BSColor.Stage.accent)
                } else {
                    Text(String(format: "%02d", number)).font(.caption.monospacedDigit()).foregroundStyle(BSColor.Stage.dim)
                }
            }
            .frame(width: 28)

            Button {
                room.loadDisc(album, songID: track.id, autoplay: true)
                returnToPlayer()
            } label: {
                HStack(spacing: BSSpacing.sm) {
                    Text(track.title).font(.subheadline.weight(.medium))
                        .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.foreground).lineLimit(1)
                    Spacer(minLength: 0)
                    if let duration = track.duration, duration > 0 {
                        let mins = Int(duration) / 60
                        let secs = Int(duration) % 60
                        Text(String(format: "%d:%02d", mins, secs))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, BSSpacing.sm).padding(.vertical, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border.opacity(0.5)).frame(height: 1).padding(.leading, 40) }
    }

    private var albums: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                Text(BSLocalization.text("专辑")).font(.title3.bold())
                Spacer()
                Text(String(format: "%02d", artist.albums.count)).font(.caption.monospacedDigit()).foregroundStyle(BSColor.Stage.dim)
            }
            LazyVStack(spacing: BSSpacing.sm) {
                ForEach(artist.albums) { album in
                    DisclosureGroup {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                                albumTrackRow(track, number: index + 1, album: album)
                            }
                        }
                        .padding(.top, BSSpacing.xs)
                    } label: {
                        HStack(spacing: BSSpacing.md) {
                            ListeningArtwork(url: album.artworkURL, title: album.title)
                                .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                Text(album.title).font(.headline).foregroundStyle(BSColor.Stage.foreground).lineLimit(2)
                                Text("\(album.tracks.count) " + BSLocalization.text("首")).font(.caption).foregroundStyle(BSColor.Stage.muted)
                            }
                            Spacer(minLength: 0)
                            Button {
                                room.loadDisc(album, autoplay: true)
                                returnToPlayer()
                            } label: {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 15))
                                    .foregroundStyle(BSColor.Stage.foreground)
                                    .frame(width: 36, height: 36)
                                    .background(BSColor.Stage.surfaceRaised, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(BSLocalization.text("装入 CD 播放"))
                        }.padding(BSSpacing.sm)
                    }
                    .tint(BSColor.Stage.muted)
                    .background(BSColor.Stage.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: BSRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
                }
            }
        }
    }
}
