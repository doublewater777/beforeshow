import Foundation

struct ListeningDiscTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artistName: String
    let duration: TimeInterval?
    let previewURL: URL?
    init(_ song: CatalogSong) {
        id = song.appleMusicSongID; title = song.title; artistName = song.artistName
        duration = song.duration; previewURL = song.previewURL.flatMap(URL.init(string:))
    }
    var playbackItem: ListeningPlaybackItem {
        ListeningPlaybackItem(songID: id, duration: duration, previewURL: previewURL)
    }
}

struct ListeningDisc: Identifiable, Equatable {
    let id: String
    let title: String
    let artworkURL: URL?
    let tracks: [ListeningDiscTrack]
}

/// An album remains a multi-track container. Queue entries only define the
/// preparation disc; album track order never becomes a collection of single CDs.
@MainActor enum ListeningDiscAssembler {
    static func discs(albums: [CatalogAlbum], songs: [CatalogSong], queue: [ListeningQueueEntry]) -> [ListeningDisc] {
        let songsByID = Dictionary(songs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { first, _ in first })
        let allowed = Set(queue.map(\.songID))
        let warmup = queue.compactMap { songsByID[$0.songID].map(ListeningDiscTrack.init) }
        var result: [ListeningDisc] = warmup.isEmpty ? [] : [
            ListeningDisc(id: "preparation", title: BSLocalization.text("开场前"), artworkURL: nil, tracks: warmup)
        ]
        result += albums.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }.compactMap { album in
            let tracks = album.orderedTrackIDs.filter { allowed.contains($0) }.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
            guard !tracks.isEmpty else { return nil }
            return ListeningDisc(id: album.appleMusicAlbumID, title: album.title,
                                 artworkURL: album.artworkURL.flatMap(URL.init(string:)), tracks: tracks)
        }
        return result
    }
}
