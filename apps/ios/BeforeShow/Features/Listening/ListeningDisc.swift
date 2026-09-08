import Foundation

struct ListeningDiscTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artistName: String
    let artworkURL: URL?
    let duration: TimeInterval?
    let previewURL: URL?
    init(_ song: CatalogSong) {
        id = song.appleMusicSongID; title = song.title; artistName = song.artistName
        artworkURL = song.artworkURL.flatMap(URL.init(string:))
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
    let artistNames: [String]
    let editorialText: String?
    let genreNames: [String]
    let releaseDate: Date?
    let copyright: String?
    let recordLabelName: String?
    let contentRatingRawValue: String?
    let audioVariantRawValues: [String]
    let isAppleDigitalMaster: Bool?
    let isCompilation: Bool?
    let isSingle: Bool?
    let appleMusicURL: URL?

    init(
        id: String,
        title: String,
        artworkURL: URL?,
        tracks: [ListeningDiscTrack],
        artistNames: [String] = [],
        editorialText: String? = nil,
        genreNames: [String] = [],
        releaseDate: Date? = nil,
        copyright: String? = nil,
        recordLabelName: String? = nil,
        contentRatingRawValue: String? = nil,
        audioVariantRawValues: [String] = [],
        isAppleDigitalMaster: Bool? = nil,
        isCompilation: Bool? = nil,
        isSingle: Bool? = nil,
        appleMusicURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artworkURL = artworkURL
        self.tracks = tracks
        self.artistNames = artistNames
        self.editorialText = editorialText
        self.genreNames = genreNames
        self.releaseDate = releaseDate
        self.copyright = copyright
        self.recordLabelName = recordLabelName
        self.contentRatingRawValue = contentRatingRawValue
        self.audioVariantRawValues = audioVariantRawValues
        self.isAppleDigitalMaster = isAppleDigitalMaster
        self.isCompilation = isCompilation
        self.isSingle = isSingle
        self.appleMusicURL = appleMusicURL
    }
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
        result += albums.sorted { a, b in a.releaseDate == b.releaseDate ? a.appleMusicAlbumID < b.appleMusicAlbumID : (a.releaseDate ?? .distantPast) > (b.releaseDate ?? .distantPast) }.compactMap { album in
            let tracks = album.orderedTrackIDs.filter { allowed.contains($0) }.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
            guard !tracks.isEmpty else { return nil }
            return ListeningDisc(id: album.appleMusicAlbumID, title: album.title,
                                 artworkURL: album.artworkURL.flatMap(URL.init(string:)), tracks: tracks,
                                 artistNames: album.artistNames, editorialText: album.editorialText,
                                 genreNames: album.genreNames, releaseDate: album.releaseDate,
                                 copyright: album.copyright, recordLabelName: album.recordLabelName,
                                 contentRatingRawValue: album.contentRatingRawValue,
                                 audioVariantRawValues: album.audioVariantRawValues,
                                 isAppleDigitalMaster: album.isAppleDigitalMaster,
                                 isCompilation: album.isCompilation, isSingle: album.isSingle,
                                 appleMusicURL: album.appleMusicURL.flatMap(URL.init(string:)))
        }
        return result
    }
}
