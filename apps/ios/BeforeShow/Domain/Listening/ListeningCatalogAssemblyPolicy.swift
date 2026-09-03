import Foundation

struct ListeningCatalogTrackCandidate: Equatable, Sendable {
    let songID: String
    let performerArtistIDs: [String]
}

struct ListeningCatalogAlbumCandidate: Equatable, Sendable {
    let albumID: String
    let isCompilation: Bool
    let tracks: [ListeningCatalogTrackCandidate]
}

struct ListeningCatalogAssembly: Equatable, Sendable {
    let orderedSongIDs: [String]
    let retainedTrackIDsByAlbumID: [String: [String]]
    let retainedAlbumIDs: [String]
}

enum ListeningCatalogAssemblyPolicy {
    static func assemble(
        targetArtistID: String,
        topSongIDs: [String],
        albums: [ListeningCatalogAlbumCandidate]
    ) -> ListeningCatalogAssembly {
        var seenSongIDs = Set<String>()
        var orderedSongIDs: [String] = []
        var retainedTrackIDsByAlbumID: [String: [String]] = [:]
        var retainedAlbumIDs: [String] = []

        for songID in topSongIDs where seenSongIDs.insert(songID).inserted {
            orderedSongIDs.append(songID)
        }

        for album in albums {
            var retainedTrackIDs: [String] = []
            for track in album.tracks {
                if album.isCompilation,
                   !track.performerArtistIDs.contains(targetArtistID) {
                    continue
                }
                if !retainedTrackIDs.contains(track.songID) {
                    retainedTrackIDs.append(track.songID)
                }
                if seenSongIDs.insert(track.songID).inserted {
                    orderedSongIDs.append(track.songID)
                }
            }

            if album.isCompilation, retainedTrackIDs.isEmpty {
                continue
            }
            retainedAlbumIDs.append(album.albumID)
            retainedTrackIDsByAlbumID[album.albumID] = retainedTrackIDs
        }

        return ListeningCatalogAssembly(
            orderedSongIDs: orderedSongIDs,
            retainedTrackIDsByAlbumID: retainedTrackIDsByAlbumID,
            retainedAlbumIDs: retainedAlbumIDs
        )
    }
}
