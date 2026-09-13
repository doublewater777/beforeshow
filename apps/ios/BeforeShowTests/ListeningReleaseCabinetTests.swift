import XCTest
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningReleaseCabinetTests: XCTestCase {
    func testArtistCabinetIncludesEPAndSingleReleases() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "a" }
        )

        context.insert(CatalogAlbum(
            appleMusicAlbumID: "fixture-ep",
            title: "Fixture EP",
            artistIDs: ["a"],
            isSingle: false,
            orderedTrackIDs: ["a1", "a2"]
        ))
        context.insert(CatalogAlbum(
            appleMusicAlbumID: "fixture-single",
            title: "Fixture Single",
            artistIDs: ["a"],
            isSingle: true,
            orderedTrackIDs: ["a1"]
        ))
        snapshot.albumIDs.append(contentsOf: ["fixture-ep", "fixture-single"])
        try context.save()

        let room = ListenTestData.room(context)
        await room.load(show: show)
        room.selectScope(.artist("a"))

        XCTAssertTrue(room.libraryDiscs.contains { $0.id == "fixture-ep" })
        XCTAssertTrue(room.libraryDiscs.contains { $0.id == "fixture-single" })
        XCTAssertTrue(room.discs.contains { $0.id == "fixture-ep" })
        XCTAssertTrue(room.discs.contains { $0.id == "fixture-single" })
    }

    func testFeaturedPlaylistsAppearBeforeReleasesAndPreserveTrackOrder() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "a" }
        )
        context.insert(CatalogSong(
            appleMusicSongID: "playlist-guest",
            title: "Playlist Guest",
            artistName: "Guest Artist",
            duration: 180
        ))
        let playlist = ListeningCatalogPlaylistPayload(
            playlistID: "featured-playlist",
            name: "Artist Essentials",
            artworkURL: "https://example.com/playlist.jpg",
            curatorName: "Apple Music",
            descriptionText: "Featured by Apple Music",
            appleMusicURL: "https://music.apple.com/playlist/featured",
            orderedTrackIDs: ["a2", "playlist-guest", "a1"]
        )
        _ = try ListeningRepository(modelContext: context).upsertArtistCatalogSnapshot(
            artistID: snapshot.artistID,
            artistName: snapshot.artistName,
            artworkURL: snapshot.artworkURL,
            editorialText: snapshot.editorialText,
            genreNames: snapshot.genreNames,
            orderedSongIDs: snapshot.orderedSongIDs,
            topSongIDs: snapshot.topSongIDs,
            albumIDs: snapshot.albumIDs,
            featuredPlaylists: [playlist],
            fetchedAt: snapshot.fetchedAt
        )
        try context.save()

        let room = ListenTestData.room(context)
        await room.load(show: show)
        room.selectScope(.artist("a"))

        let discs = room.libraryDiscs
        let featured = try XCTUnwrap(discs.first)
        XCTAssertEqual(featured.id, "featured-playlist")
        XCTAssertEqual(featured.tracks.map(\.id), ["a2", "playlist-guest", "a1"])
        if case let .featuredPlaylist(artistID) = featured.origin {
            XCTAssertEqual(artistID, "a")
        } else {
            XCTFail("Expected featured playlist disc origin")
        }
        XCTAssertEqual(discs.dropFirst().first?.id, "album")
        XCTAssertFalse(snapshot.orderedSongIDs.contains("playlist-guest"))
    }

    func testFeaturedPlaylistSnapshotRoundTripsThroughPersistence() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let playlist = ListeningCatalogPlaylistPayload(
            playlistID: "featured",
            name: "Featured",
            artworkURL: nil,
            curatorName: "Apple Music",
            descriptionText: nil,
            appleMusicURL: "https://music.apple.com/playlist/featured",
            orderedTrackIDs: ["one", "two"]
        )
        _ = try ListeningRepository(modelContext: context).upsertArtistCatalogSnapshot(
            artistID: "artist",
            artistName: "Artist",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: ["one"],
            topSongIDs: ["one"],
            albumIDs: [],
            featuredPlaylists: [playlist],
            fetchedAt: Date()
        )
        try context.save()

        let reopened = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "artist" }
        )
        XCTAssertEqual(reopened.featuredPlaylists, [playlist])
        XCTAssertEqual(reopened.orderedSongIDs, ["one"])
    }
}
