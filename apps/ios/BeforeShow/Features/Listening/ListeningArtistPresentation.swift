import Foundation
import SwiftData

struct ListeningArtistPresentation: Identifiable {
    let id: String
    let name: String
    let artworkURL: URL?
    let editorialText: String?
    let genres: [String]
    let top: [ListeningDiscTrack]
    let all: [ListeningDiscTrack]
    let albums: [ListeningDisc]
}

@MainActor extension ListeningRoomCoordinator {
    func artistPresentation(_ id: String) -> ListeningArtistPresentation? {
        artistPresentations[id]
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
        let release = artist.albums.first { disc in
            guard case .album = disc.origin else { return false }
            return disc.tracks.contains { $0.id == track.id }
        }
        let disc = release
            ?? artist.albums.first { $0.tracks.contains { $0.id == track.id } }
            ?? ListeningDisc(id: "artist-\(artistID)", title: artist.name, artworkURL: artist.artworkURL, tracks: artist.all)
        loadDisc(disc, songID: track.id, autoplay: true)
    }
}
