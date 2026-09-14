import Foundation

enum ListeningMusicAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum ListeningMusicCapability: String, Equatable, Sendable {
    case fullPlayback
    case previewOnly
    case metadataOnly
    case unavailable
}

struct ListeningMusicAccess: Equatable, Sendable {
    let authorizationStatus: ListeningMusicAuthorizationStatus
    let canPlayCatalogContent: Bool
}

enum ListeningMusicCapabilityResolver {
    static func resolve(
        access: ListeningMusicAccess,
        hasPreviewAsset: Bool,
        hasCatalogMetadata: Bool
    ) -> ListeningMusicCapability {
        if access.authorizationStatus == .authorized, access.canPlayCatalogContent {
            return .fullPlayback
        }
        if hasPreviewAsset {
            return .previewOnly
        }
        if hasCatalogMetadata {
            return .metadataOnly
        }
        return .unavailable
    }
}

enum ListeningCatalogError: Error, Equatable {
    case authorizationRequired
    case artistNotFound(String)
    case incompleteCatalog(String)
}

struct ListeningCatalogSongPayload: Equatable, Sendable {
    let songID: String
    let title: String
    let artistName: String
    let albumID: String?
    let albumTitle: String?
    let artworkURL: String?
    let duration: TimeInterval?
    let performerArtistIDs: [String]
    let performerArtistNames: [String]
    let previewURL: String?
}

struct ListeningCatalogAlbumPayload: Equatable, Sendable {
    let albumID: String
    let title: String
    let artworkURL: String?
    let releaseDate: Date?
    let artistIDs: [String]
    let artistNames: [String]
    let editorialText: String?
    let genreNames: [String]
    let copyright: String?
    let recordLabelName: String?
    let contentRatingRawValue: String?
    let audioVariantRawValues: [String]
    let isAppleDigitalMaster: Bool?
    let isCompilation: Bool?
    let isSingle: Bool?
    let appleMusicURL: String?
    let orderedTrackIDs: [String]

    init(
        albumID: String,
        title: String,
        artworkURL: String?,
        releaseDate: Date?,
        artistIDs: [String],
        artistNames: [String] = [],
        editorialText: String? = nil,
        genreNames: [String] = [],
        copyright: String? = nil,
        recordLabelName: String? = nil,
        contentRatingRawValue: String? = nil,
        audioVariantRawValues: [String] = [],
        isAppleDigitalMaster: Bool? = nil,
        isCompilation: Bool? = nil,
        isSingle: Bool? = nil,
        appleMusicURL: String? = nil,
        orderedTrackIDs: [String]
    ) {
        self.albumID = albumID
        self.title = title
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.artistIDs = artistIDs
        self.artistNames = artistNames
        self.editorialText = editorialText
        self.genreNames = genreNames
        self.copyright = copyright
        self.recordLabelName = recordLabelName
        self.contentRatingRawValue = contentRatingRawValue
        self.audioVariantRawValues = audioVariantRawValues
        self.isAppleDigitalMaster = isAppleDigitalMaster
        self.isCompilation = isCompilation
        self.isSingle = isSingle
        self.appleMusicURL = appleMusicURL
        self.orderedTrackIDs = orderedTrackIDs
    }
}

struct ListeningCatalogPlaylistPayload: Codable, Equatable, Sendable {
    let playlistID: String
    let name: String
    let artworkURL: String?
    let curatorName: String?
    let descriptionText: String?
    let appleMusicURL: String?
    let orderedTrackIDs: [String]
}

struct ListeningArtistCatalogPayload: Equatable, Sendable {
    let artistID: String
    let artistName: String
    let artworkURL: String?
    let editorialText: String?
    let genreNames: [String]
    let orderedSongIDs: [String]
    let topSongIDs: [String]
    let albumIDs: [String]
    let featuredPlaylists: [ListeningCatalogPlaylistPayload]
    let songs: [ListeningCatalogSongPayload]
    let albums: [ListeningCatalogAlbumPayload]
    let fetchedAt: Date

    init(
        artistID: String,
        artistName: String,
        artworkURL: String?,
        editorialText: String?,
        genreNames: [String],
        orderedSongIDs: [String],
        topSongIDs: [String],
        albumIDs: [String],
        featuredPlaylists: [ListeningCatalogPlaylistPayload] = [],
        songs: [ListeningCatalogSongPayload],
        albums: [ListeningCatalogAlbumPayload],
        fetchedAt: Date
    ) {
        self.artistID = artistID
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.editorialText = editorialText
        self.genreNames = genreNames
        self.orderedSongIDs = orderedSongIDs
        self.topSongIDs = topSongIDs
        self.albumIDs = albumIDs
        self.featuredPlaylists = featuredPlaylists
        self.songs = songs
        self.albums = albums
        self.fetchedAt = fetchedAt
    }
}

struct ListeningFeaturedPlaylistsPayload: Equatable, Sendable {
    let artistID: String
    let playlists: [ListeningCatalogPlaylistPayload]
    let songs: [ListeningCatalogSongPayload]
    let fetchedAt: Date
}

protocol ListeningMusicCatalogServicing: Sendable {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus
    func currentAccess() async -> ListeningMusicAccess
    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload]
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload
    func fetchFeaturedPlaylists(artistID: String, fetchedAt: Date) async throws -> ListeningFeaturedPlaylistsPayload
}

enum ListeningCatalogRefreshPolicy {
    static let maximumAge: TimeInterval = 24 * 60 * 60

    static func shouldRefresh(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= maximumAge
    }
}

extension ListeningMusicCatalogServicing {
    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] { [] }

    func fetchFeaturedPlaylists(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningFeaturedPlaylistsPayload {
        ListeningFeaturedPlaylistsPayload(
            artistID: artistID,
            playlists: [],
            songs: [],
            fetchedAt: fetchedAt
        )
    }
}
