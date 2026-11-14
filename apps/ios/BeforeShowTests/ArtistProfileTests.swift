import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistProfileTests: XCTestCase {
    func testArtistProfileLoadsReleasesAndFeaturedPlaylists() async throws {
        let (container, _) = try ListenTestData.make()
        let context = container.mainContext
        let service = StubArtistProfileCatalogService(hasPlaylists: true)

        let reference = ArtistReference(name: "A", appleMusicArtistID: "a")
        let model = ArtistProfileModel(reference: reference, service: service)

        await model.load(in: context)

        XCTAssertEqual(model.status, .ready)
        XCTAssertFalse(model.releases.isEmpty)
        XCTAssertEqual(model.playlists.count, 1)
        let playlist = try XCTUnwrap(model.playlists.first)
        XCTAssertEqual(playlist.id, "playlist-1")
        XCTAssertEqual(playlist.title, "Artist Essentials")
        if case let .featuredPlaylist(artistID) = playlist.origin {
            XCTAssertEqual(artistID, "a")
        } else {
            XCTFail("Expected featured playlist origin")
        }
    }

    func testArtistProfileWithNoPlaylistsLeavesPlaylistsEmpty() async throws {
        let (container, _) = try ListenTestData.make()
        let context = container.mainContext
        let service = StubArtistProfileCatalogService(hasPlaylists: false)

        let reference = ArtistReference(name: "A", appleMusicArtistID: "a")
        let model = ArtistProfileModel(reference: reference, service: service)

        await model.load(in: context)

        XCTAssertEqual(model.status, .ready)
        XCTAssertFalse(model.releases.isEmpty)
        XCTAssertTrue(model.playlists.isEmpty)
    }

    func testArtistProfilePlaylistFetchFailureDoesNotFailProfile() async throws {
        let (container, _) = try ListenTestData.make()
        let context = container.mainContext
        let service = StubArtistProfileCatalogService(failsPlaylists: true)

        let reference = ArtistReference(name: "A", appleMusicArtistID: "a")
        let model = ArtistProfileModel(reference: reference, service: service)

        await model.load(in: context)

        XCTAssertEqual(model.status, .ready)
        XCTAssertFalse(model.releases.isEmpty)
        XCTAssertTrue(model.playlists.isEmpty)
    }
}

private final class StubArtistProfileCatalogService: ListeningMusicCatalogServicing, @unchecked Sendable {
    private let hasPlaylists: Bool
    private let failsPlaylists: Bool

    init(hasPlaylists: Bool = false, failsPlaylists: Bool = false) {
        self.hasPlaylists = hasPlaylists
        self.failsPlaylists = failsPlaylists
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: "Artist \(artistID)",
            artworkURL: nil,
            editorialText: nil,
            genreNames: ["Rock"],
            orderedSongIDs: ["s1"],
            topSongIDs: ["s1"],
            albumIDs: ["alb1"],
            featuredPlaylists: [],
            songs: [
                ListeningCatalogSongPayload(
                    songID: "s1",
                    title: "Song 1",
                    artistName: "Artist \(artistID)",
                    albumID: "alb1",
                    albumTitle: "Album 1",
                    artworkURL: nil,
                    duration: 180,
                    performerArtistIDs: [artistID],
                    performerArtistNames: ["Artist \(artistID)"],
                    previewURL: nil
                )
            ],
            albums: [
                ListeningCatalogAlbumPayload(
                    albumID: "alb1",
                    title: "Album 1",
                    artworkURL: nil,
                    releaseDate: Date(),
                    artistIDs: [artistID],
                    orderedTrackIDs: ["s1"]
                )
            ],
            fetchedAt: fetchedAt
        )
    }

    func fetchFeaturedPlaylists(artistID: String, fetchedAt: Date) async throws -> ListeningFeaturedPlaylistsPayload {
        if failsPlaylists {
            throw URLError(.badServerResponse)
        }
        guard hasPlaylists else {
            return ListeningFeaturedPlaylistsPayload(artistID: artistID, playlists: [], songs: [], fetchedAt: fetchedAt)
        }
        let songID = "song-\(artistID)-1"
        return ListeningFeaturedPlaylistsPayload(
            artistID: artistID,
            playlists: [
                ListeningCatalogPlaylistPayload(
                    playlistID: "playlist-1",
                    name: "Artist Essentials",
                    artworkURL: nil,
                    curatorName: "Apple Music",
                    descriptionText: "Essentials",
                    appleMusicURL: nil,
                    orderedTrackIDs: [songID]
                )
            ],
            songs: [
                ListeningCatalogSongPayload(
                    songID: songID,
                    title: "Song 1",
                    artistName: "Artist \(artistID)",
                    albumID: nil,
                    albumTitle: nil,
                    artworkURL: nil,
                    duration: 180,
                    performerArtistIDs: [artistID],
                    performerArtistNames: ["Artist \(artistID)"],
                    previewURL: nil
                )
            ],
            fetchedAt: fetchedAt
        )
    }
}
