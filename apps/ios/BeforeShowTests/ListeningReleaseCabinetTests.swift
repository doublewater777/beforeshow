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
        room.mechanism.motion.stop()
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
        room.mechanism.motion.stop()
    }

    func testArtistLibraryPlaybackPrefersFormalAlbumWhenFeaturedPlaylistContainsSameSong() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        try installFeaturedPlaylist(
            in: context,
            orderedTrackIDs: ["a2"],
            playlistID: "featured-overlap"
        )

        let room = ListenTestData.room(context)
        await room.load(show: show)
        let artist = try XCTUnwrap(room.artistPresentation("a"))
        XCTAssertEqual(artist.albums.first?.id, "featured-overlap")
        let song = try XCTUnwrap(artist.all.first { $0.id == "a2" })

        room.playLibrarySong(song, artistID: "a")
        try await ListenTestData.settle(room) {
            room.mechanism.position == .seated && room.mechanism.disc?.id == "album"
        }

        XCTAssertEqual(room.mechanism.disc?.id, "album")
        if case .album = room.mechanism.disc?.origin {
            // Expected: the formal release remains the playback context.
        } else {
            XCTFail("Expected album playback context")
        }
        XCTAssertEqual(room.track?.id, "a2")
        room.stop()
        room.mechanism.motion.stop()
    }

    func testFeaturedPlaylistLoadedDiscRestoresAcrossCoordinatorRecreationWithoutAutoplay() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        try installFeaturedPlaylist(
            in: context,
            orderedTrackIDs: ["a2", "a1"],
            playlistID: "featured-cold-start"
        )

        let room = ListenTestData.room(context)
        await room.load(show: show)
        let featured = try XCTUnwrap(
            room.artistPresentation("a")?.albums.first { $0.id == "featured-cold-start" }
        )
        room.restoreDisc(featured, songID: "a1")

        let states = try context.fetch(FetchDescriptor<ListeningLoadedDiscState>())
        let state = try XCTUnwrap(states.first)
        let persisted = try JSONDecoder().decode(ListeningDisc.self, from: state.discData)
        XCTAssertEqual(persisted.id, "featured-cold-start")
        XCTAssertEqual(state.songID, "a1")
        if case let .featuredPlaylist(artistID) = persisted.origin {
            XCTAssertEqual(artistID, "a")
        } else {
            XCTFail("Expected featured playlist to survive Codable persistence")
        }

        let reopened = ListenTestData.room(context)
        XCTAssertEqual(reopened.mechanism.disc?.id, "featured-cold-start")
        XCTAssertEqual(reopened.track?.id, "a1")
        if case let .featuredPlaylist(artistID) = reopened.mechanism.disc?.origin {
            XCTAssertEqual(artistID, "a")
        } else {
            XCTFail("Expected restored featured playlist origin")
        }
        XCTAssertEqual(reopened.playbackState, .idle)
        XCTAssertFalse(reopened.isPlaying)

        await reopened.load(show: show)
        XCTAssertEqual(reopened.mechanism.disc?.id, "featured-cold-start")
        XCTAssertEqual(reopened.track?.id, "a1")
        XCTAssertFalse(reopened.isPlaying)
        room.mechanism.motion.stop()
        reopened.mechanism.motion.stop()
    }

    func testPlaylistOnlyGuestFamiliarityDoesNotChangeTargetArtistCountTierOrDenominator() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        context.insert(CatalogSong(
            appleMusicSongID: "playlist-guest",
            title: "Playlist Guest",
            artistName: "Guest Artist",
            duration: 180
        ))
        try installFeaturedPlaylist(
            in: context,
            orderedTrackIDs: ["playlist-guest", "a2"],
            playlistID: "featured-guest"
        )

        let beforeRoom = ListenTestData.room(context)
        await beforeRoom.load(show: show)
        let before = try XCTUnwrap(beforeRoom.artistPresentation("a"))
        let beforeDenominator = before.all.count
        XCTAssertEqual(beforeDenominator, 2)
        XCTAssertEqual(before.familiarCount, 0)

        _ = try ListeningRepository(modelContext: context)
            .confirmActualFamiliarity(songID: "playlist-guest", at: Date())
        try context.save()

        let afterRoom = ListenTestData.room(context)
        await afterRoom.load(show: show)
        let after = try XCTUnwrap(afterRoom.artistPresentation("a"))
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "a" }
        )

        XCTAssertTrue(afterRoom.familiarSongIDs.contains("playlist-guest"), "fixture must contain real familiarity evidence")
        XCTAssertFalse(snapshot.orderedSongIDs.contains("playlist-guest"))
        XCTAssertEqual(snapshot.orderedSongIDs.count, beforeDenominator)
        XCTAssertEqual(after.all.count, beforeDenominator)
        XCTAssertEqual(after.familiarCount, before.familiarCount)
        XCTAssertEqual(after.tier, before.tier)
        beforeRoom.mechanism.motion.stop()
        afterRoom.mechanism.motion.stop()
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

    private func installFeaturedPlaylist(
        in context: ModelContext,
        orderedTrackIDs: [String],
        playlistID: String
    ) throws {
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "a" }
        )
        let playlist = ListeningCatalogPlaylistPayload(
            playlistID: playlistID,
            name: "Artist Essentials",
            artworkURL: "https://example.com/playlist.jpg",
            curatorName: "Apple Music",
            descriptionText: "Featured by Apple Music",
            appleMusicURL: "https://music.apple.com/playlist/featured",
            orderedTrackIDs: orderedTrackIDs
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
    }
}
