import Foundation

struct ListeningDiscTrack: Identifiable, Equatable, Codable {
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
        ListeningPlaybackItem(
            songID: id,
            duration: duration,
            previewURL: previewURL,
            title: title,
            artistName: artistName
        )
    }
}

struct ListeningDisc: Identifiable, Equatable, Codable {
    enum Origin: Equatable, Codable {
        case album
        case featuredPlaylist(artistID: String)
        case compilation(showID: UUID, number: Int)
    }
    let origin: Origin
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
        appleMusicURL: URL? = nil,
        origin: Origin = .album
    ) {
        self.origin = origin
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

/// Apple catalog order and full track order are preserved for every physical-disc source.
@MainActor enum ListeningDiscAssembler {
    static func discs(albums: [CatalogAlbum], songsByID: [String: CatalogSong]) -> [ListeningDisc] {
        albums.map { album in
            let tracks = album.orderedTrackIDs.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
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
    }

    static func discs(
        featuredPlaylists: [ListeningCatalogPlaylistPayload],
        artistID: String,
        songsByID: [String: CatalogSong]
    ) -> [ListeningDisc] {
        featuredPlaylists.compactMap { playlist in
            let tracks = playlist.orderedTrackIDs.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
            guard !tracks.isEmpty else { return nil }
            return ListeningDisc(
                id: playlist.playlistID,
                title: playlist.name,
                artworkURL: playlist.artworkURL.flatMap(URL.init(string:)),
                tracks: tracks,
                editorialText: playlist.descriptionText,
                appleMusicURL: playlist.appleMusicURL.flatMap(URL.init(string:)),
                origin: .featuredPlaylist(artistID: artistID)
            )
        }
    }

    static func discs(albums: [CatalogAlbum], songs: [CatalogSong]) -> [ListeningDisc] {
        let songsByID = Dictionary(songs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { first, _ in first })
        return discs(albums: albums, songsByID: songsByID)
    }
}
