import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistWarmupCoordinatorTests: XCTestCase {
    func testRefreshingCompleteCatalogPersistsSnapshotSongsAndDenominator() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(
                catalogs: [
                    "artist-1": .complete(songs: [
                        makeSong(id: "song-1", title: "Top Song", source: .topSongs),
                        makeSong(id: "song-2", title: "Album Song", source: .album("album-1")),
                        makeSong(id: "song-1", title: "Duplicate", source: .album("album-1"))
                    ])
                ]
            ),
            context: context
        )

        let snapshot = try await coordinator.refreshCatalog(artistID: "artist-1")

        XCTAssertEqual(snapshot.state, .complete)
        XCTAssertEqual(snapshot.denominatorSongCount, 2)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<CatalogSong>()).map(\.appleMusicSongID)),
            ["song-1", "song-2"]
        )
    }

    func testRefreshingPartialCatalogDoesNotPublishDenominatorOrFamiliarity() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(SongFamiliarityRecord(
            songID: "song-1",
            heardAt: Date(timeIntervalSince1970: 100),
            source: .manual
        ))
        var coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(
                catalogs: ["artist-1": .partial(
                    songs: [makeSong(id: "song-1", title: "Known Song", source: .topSongs)],
                    reason: "album tracks unavailable"
                )]
            ),
            context: context
        )

        let snapshot = try await coordinator.refreshCatalog(artistID: "artist-1")

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.denominatorSongCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CatalogSong>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).count, 1)
    }

    func testWarmupQueueExcludesNotInterestedArtistsAndKeepsStablePriority() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        insertShowArtist(showID: showID, artistID: "artist-wanted", label: "Wanted", interest: .wanted, in: context)
        insertShowArtist(showID: showID, artistID: "artist-maybe", label: "Maybe", interest: .maybe, in: context)
        insertShowArtist(showID: showID, artistID: "artist-skipped", label: "Skipped", interest: .notInterested, in: context)
        context.insert(CatalogSong(
            appleMusicSongID: "song-maybe",
            title: "Maybe Song",
            performingArtistIDs: ["artist-maybe"],
            performingArtistNames: ["Maybe"],
            category: .album
        ))
        context.insert(CatalogSong(
            appleMusicSongID: "song-wanted",
            title: "Wanted Song",
            performingArtistIDs: ["artist-wanted"],
            performingArtistNames: ["Wanted"],
            category: .album
        ))
        context.insert(CatalogSong(
            appleMusicSongID: "song-skipped",
            title: "Skipped Song",
            performingArtistIDs: ["artist-skipped"],
            performingArtistNames: ["Skipped"],
            category: .album
        ))
        try context.save()
        var coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(),
            context: context
        )

        let queue = try coordinator.warmupQueue(showID: showID, scope: .allArtists)

        XCTAssertEqual(queue.map(\.id), ["song-wanted", "song-maybe"])
    }

    func testWarmupQueuePutsUnheardSongsBeforeHeardSongsForTheSameArtist() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        insertShowArtist(showID: showID, artistID: "artist-wanted", label: "Wanted", interest: .wanted, in: context)
        context.insert(CatalogSong(
            appleMusicSongID: "song-heard",
            title: "Heard Song",
            performingArtistIDs: ["artist-wanted"],
            performingArtistNames: ["Wanted"],
            category: .album
        ))
        context.insert(CatalogSong(
            appleMusicSongID: "song-unheard",
            title: "Unheard Song",
            performingArtistIDs: ["artist-wanted"],
            performingArtistNames: ["Wanted"],
            category: .album
        ))
        context.insert(SongFamiliarityRecord(songID: "song-heard", heardAt: Date(), source: .manual))
        try context.save()
        let coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(),
            context: context
        )

        let queue = try coordinator.warmupQueue(showID: showID, scope: .allArtists)

        XCTAssertEqual(queue.map(\.id), ["song-unheard", "song-heard"])
    }

    func testFullPlaybackEvidenceMarksHeardOnlyOnceAndPreviewNeverDoes() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(),
            context: context
        )

        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 10, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 39, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 68, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 97, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 98, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 99, isPlaying: true)))
        XCTAssertTrue(try coordinator.ingestPlaybackSample(makeSample(currentTime: 100, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 120, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(
            currentTime: 10,
            source: .appleMusicPreview,
            isPlaying: true
        )))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(records.map(\.songID), ["song-1"])
        XCTAssertEqual(records[0].source, .auto)
    }

    func testForwardSeekDoesNotCreateFamiliarity() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var coordinator = ArtistWarmupCoordinator(
            service: FixtureArtistWarmupMusicService(),
            context: context
        )

        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 10, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 150, isPlaying: true)))
        XCTAssertFalse(try coordinator.ingestPlaybackSample(makeSample(currentTime: 179, isPlaying: true)))

        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
    }

    private func insertShowArtist(
        showID: UUID,
        artistID: String,
        label: String,
        interest: ArtistInterest,
        in context: ModelContext
    ) {
        let artist = ShowArtist(
            showID: showID,
            originalArtistLabel: label,
            originalOrder: 0,
            interest: interest
        )
        artist.confirmAppleMusicArtist(id: artistID, name: label, artworkURL: nil)
        context.insert(artist)
    }

    private func makeSample(
        currentTime: TimeInterval,
        source: WarmupListeningEvidence.PlaybackSource = .appleMusicFullPlayback,
        isPlaying: Bool
    ) -> WarmupListeningEvidence.PlaybackSample {
        WarmupListeningEvidence.PlaybackSample(
            songID: "song-1",
            source: source,
            currentTime: currentTime,
            duration: 180,
            isPlaying: isPlaying
        )
    }

    private func makeSong(
        id: String,
        title: String,
        source: ArtistWarmupCatalogSource
    ) -> ArtistWarmupCatalogSong {
        ArtistWarmupCatalogSong(
            id: id,
            artistID: "artist-1",
            title: title,
            albumTitle: "Warmup Album",
            artistName: "Artist 1",
            performerArtistIDs: ["artist-1"],
            performerNames: ["Artist 1"],
            duration: 180,
            source: source,
            previewFallbackURL: nil
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ShowArtist.self,
            ArtistCatalogSnapshot.self,
            CatalogSong.self,
            SongFamiliarityRecord.self,
            ShowSongImpression.self,
            ShowArtistFamiliaritySnapshot.self,
            ShowSetlistMemory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
