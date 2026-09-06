import SwiftUI

struct ListeningLibraryView: View {
    @Bindable var room: ListeningRoomCoordinator
    let artist: ListeningArtistPresentation
    let returnToPlayer: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.lg) {
            if !artist.top.isEmpty { songs(artist.top, title: "热门") }
            songs(artist.all, title: "全部")
            if !artist.albums.isEmpty {
                Text(BSLocalization.text("专辑")).font(.title2.bold())
                ForEach(artist.albums) { album in
                    DisclosureGroup {
                        ForEach(album.tracks) { track in song(track) }
                    } label: {
                        HStack {
                            ListeningArtwork(url: album.artworkURL, title: album.title).frame(width: 56, height: 56)
                            Text(album.title).font(.headline)
                        }.padding(.vertical, BSSpacing.sm)
                    }
                }
            }
        }
    }
    private func songs(_ tracks: [ListeningDiscTrack], title: String) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text(title)).font(.title2.bold())
            ForEach(tracks) { track in song(track) }
        }
    }
    private func song(_ track: ListeningDiscTrack) -> some View {
        HStack {
            Button { room.playLibrarySong(track, artistID: artist.id); returnToPlayer() } label: {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(track.title).font(.body)
                    Text(track.artistName).font(.caption).foregroundStyle(BSColor.Stage.muted)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            ListeningWantedButton(room: room, songID: track.id)
        }
    }
}
