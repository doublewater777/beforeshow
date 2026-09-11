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
                ListeningDisc(id: $0.appleMusicAlbumID, title: $0.title,
                              artworkURL: $0.artworkURL.flatMap(URL.init(string:)), tracks: tracks($0.orderedTrackIDs),
                              artistNames: $0.artistNames, editorialText: $0.editorialText,
                              genreNames: $0.genreNames, releaseDate: $0.releaseDate,
                              copyright: $0.copyright, recordLabelName: $0.recordLabelName,
                              contentRatingRawValue: $0.contentRatingRawValue,
                              audioVariantRawValues: $0.audioVariantRawValues,
                              isAppleDigitalMaster: $0.isAppleDigitalMaster,
                              isCompilation: $0.isCompilation, isSingle: $0.isSingle,
                              appleMusicURL: $0.appleMusicURL.flatMap(URL.init(string:)))
            })
    }
    var currentArtistID: String? {
        guard let track else { return nil }
        return show?.artists.compactMap(\.appleMusicArtistID).first { id in
            catalogSnapshots.first { $0.artistID == id }?.orderedSongIDs.contains(track.id) == true
        }
    }
    var currentTrackArtistName: String? {
        guard let track else { return nil }
        if let id = currentArtistID,
           let slot = show?.artists.first(where: { $0.appleMusicArtistID == id }) {
            return slot.name
        }
        return track.artistName
    }
    var currentAlbumTitle: String? {
        guard let track else { return nil }
        guard let albumID = catalogSongs.first(where: { $0.appleMusicSongID == track.id })?.albumID else {
            return mechanism.disc?.title
        }
        return catalogAlbums.first { $0.appleMusicAlbumID == albumID }?.title ?? mechanism.disc?.title
    }
    var cabinetArtists: [ListeningArtistPresentation] {
        var seen = Set<String>()
        return (show?.artists ?? []).compactMap { slot in
            guard let id = slot.appleMusicArtistID, seen.insert(id).inserted else { return nil }
            return artistPresentation(id)
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
