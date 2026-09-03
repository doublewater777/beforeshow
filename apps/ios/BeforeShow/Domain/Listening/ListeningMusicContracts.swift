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
    let songs: [ListeningCatalogSongPayload]
    let albums: [ListeningCatalogAlbumPayload]
    let fetchedAt: Date
}

protocol ListeningMusicCatalogServicing: Sendable {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus
    func currentAccess() async -> ListeningMusicAccess
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload
}

enum ListeningCatalogRefreshPolicy {
    static let maximumAge: TimeInterval = 24 * 60 * 60

    static func shouldRefresh(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= maximumAge
    }
}
