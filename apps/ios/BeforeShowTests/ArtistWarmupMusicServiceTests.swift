import XCTest
@testable import BeforeShow

@MainActor
final class ArtistWarmupMusicServiceTests: XCTestCase {
    func testFixtureSearchAndProfileExposeProviderSuppliedArtistData() async throws {
        let artist = ArtistWarmupArtistProfile(
            id: "artist-1",
            name: "The Chairs",
            url: URL(string: "https://music.apple.com/artist/the-chairs"),
            artworkURL: URL(string: "https://example.com/artist.jpg"),
            editorialNotes: "Provider biography",
            genreNames: ["Indie Pop"]
        )
        let service = FixtureArtistWarmupMusicService(
            candidates: [
                ArtistWarmupArtistCandidate(id: "artist-1", name: "The Chairs", artworkURL: artist.artworkURL),
                ArtistWarmupArtistCandidate(id: "artist-2", name: "Another Band", artworkURL: nil)
            ],
            profiles: ["artist-1": artist]
        )

        let candidates = try await service.searchArtistCandidates(query: "chairs", limit: 5)
        let profile = try await service.fetchProviderArtistProfile(artistID: "artist-1")

        XCTAssertEqual(candidates.map(\.id), ["artist-1"])
        XCTAssertEqual(profile, artist)
    }

    func testFixtureEnumerationDedupesBySongIDAndPreservesFirstOccurrence() async {
        let service = FixtureArtistWarmupMusicService(
            catalogs: [
                "artist-1": .complete(songs: [
                    makeSong(id: "song-1", title: "First Top Song", source: .topSongs),
                    makeSong(id: "song-2", title: "Album Track", source: .album("album-1")),
                    makeSong(id: "song-1", title: "Duplicate Album Copy", source: .album("album-1"))
                ])
            ]
        )

        let catalog = await service.enumerateAudioCatalog(artistID: "artist-1")

        XCTAssertEqual(catalog.completeness, .complete)
        XCTAssertEqual(catalog.songs.map(\.id), ["song-1", "song-2"])
        XCTAssertEqual(catalog.songs[0].title, "First Top Song")
        XCTAssertEqual(catalog.songIDsForFamiliarity, ["song-1", "song-2"])
    }

    func testFixtureEnumerationMarksPartialWhenProviderCannotGuaranteeCompleteness() async {
        let service = FixtureArtistWarmupMusicService(
            catalogs: [
                "artist-1": .partial(
                    songs: [makeSong(id: "song-1", title: "Known Song", source: .topSongs)],
                    reason: "album tracks unavailable"
                )
            ]
        )

        let catalog = await service.enumerateAudioCatalog(artistID: "artist-1")

        XCTAssertEqual(catalog.completeness, .partial(reason: "album tracks unavailable"))
        XCTAssertEqual(catalog.songIDsForFamiliarity, ["song-1"])
    }

    func testFixtureExposesCapabilitySeparatelyFromScopedPlayback() async throws {
        let service = FixtureArtistWarmupMusicService(
            authorizationStatus: .authorized,
            subscriptionCapability: ArtistWarmupSubscriptionCapability(
                canPlayCatalogContent: true,
                canBecomeSubscriber: false,
                hasCloudLibraryEnabled: true
            )
        )
        let songs = [
            makeSong(id: "song-1", title: "Artist Song", artistID: "artist-1", source: .topSongs),
            makeSong(id: "song-2", title: "Other Song", artistID: "artist-2", source: .topSongs)
        ]

        let authorizationStatus = await service.authorizationStatus()
        let subscriptionCapability = try await service.subscriptionCapability()

        XCTAssertEqual(authorizationStatus, .authorized)
        XCTAssertEqual(
            subscriptionCapability,
            ArtistWarmupSubscriptionCapability(
                canPlayCatalogContent: true,
                canBecomeSubscriber: false,
                hasCloudLibraryEnabled: true
            )
        )

        try await service.enqueue(songs, scopedTo: .artist("artist-1"))
        try await service.play()
        try await service.skipToNextSong()
        try await service.skipToPreviousSong()
        await service.pause()

        XCTAssertEqual(service.enqueuedSongIDs, ["song-1"])
        XCTAssertEqual(
            service.playbackEvents,
            [.enqueue(["song-1"]), .play, .skipToNextSong, .skipToPreviousSong, .pause]
        )
    }

    private func makeSong(
        id: String,
        title: String,
        artistID: String = "artist-1",
        source: ArtistWarmupCatalogSource
    ) -> ArtistWarmupCatalogSong {
        ArtistWarmupCatalogSong(
            id: id,
            artistID: artistID,
            title: title,
            albumTitle: "Warmup Album",
            artistName: "The Chairs",
            performerArtistIDs: [artistID],
            performerNames: ["The Chairs"],
            duration: 180,
            source: source,
            previewFallbackURL: URL(string: "https://example.com/\(id).m4a")
        )
    }
}
