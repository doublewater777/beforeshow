import Foundation
import SwiftData

struct ListeningArtistPresentation: Identifiable {
    let id: String
    let name: String
    let artworkURL: URL?
    let editorialText: String?
    let genres: [String]
    let tier: ListeningFamiliarityTier?
    let familiarCount: Int
    let top: [ListeningDiscTrack]
    let all: [ListeningDiscTrack]
    let albums: [ListeningDisc]
}

@MainActor extension ListeningRoomCoordinator {
    func artistPresentation(_ id: String) -> ListeningArtistPresentation? {
        guard let snapshot = catalogSnapshots.first(where: { $0.artistID == id }) else { return nil }
        let byID = Dictionary(catalogSongs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { a, _ in a })
        func tracks(_ ids: [String]) -> [ListeningDiscTrack] { ids.compactMap { byID[$0].map(ListeningDiscTrack.init) } }
        let familiar = snapshot.orderedSongIDs.filter { familiarSongIDs.contains($0) }.count
        let albumsByID = Dictionary(catalogAlbums.map { ($0.appleMusicAlbumID, $0) }, uniquingKeysWith: { a, _ in a })
        return ListeningArtistPresentation(id: id, name: snapshot.artistName,
            artworkURL: snapshot.artworkURL.flatMap(URL.init(string:)), editorialText: snapshot.editorialText,
            genres: snapshot.genreNames,
            tier: openingTiers.first { $0.artistID == id }.flatMap { ListeningFamiliarityTier(rawValue: $0.tierRawValue) }
                ?? (show.map { WantsLivePolicy.isMutable(show: $0) } == true ? ListeningFamiliarityTier.resolve(familiarCount: familiar, totalCount: snapshot.orderedSongIDs.count) : nil),
            familiarCount: familiar, top: tracks(snapshot.topSongIDs), all: tracks(snapshot.orderedSongIDs),
            albums: snapshot.albumIDs.compactMap { albumsByID[$0] }.map {
                ListeningDisc(id: $0.appleMusicAlbumID, title: $0.title, artworkURL: $0.artworkURL.flatMap(URL.init(string:)), tracks: tracks($0.orderedTrackIDs))
            })
    }
    var currentArtistID: String? {
        guard let track else { return nil }
        return show?.artists.compactMap(\.appleMusicArtistID).first { id in
            catalogSnapshots.first { $0.artistID == id }?.orderedSongIDs.contains(track.id) == true
        }
    }
    var nextTrack: ListeningDiscTrack? {
        guard let disc = mechanism.disc, disc.tracks.indices.contains(trackIndex + 1) else { return nil }
        return disc.tracks[trackIndex + 1]
    }
    func playLibrarySong(_ track: ListeningDiscTrack, artistID: String) {
        guard let artist = artistPresentation(artistID) else { return }
        let album = artist.albums.first { $0.tracks.contains { $0.id == track.id } }
        let disc = album ?? ListeningDisc(id: "artist-\(artistID)", title: artist.name, artworkURL: artist.artworkURL, tracks: artist.all)
        loadDisc(disc, songID: track.id, autoplay: true)
    }
}
