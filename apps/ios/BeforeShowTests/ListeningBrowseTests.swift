import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningBrowseTests: XCTestCase {
    func testDelayedPlaybackFailureAllowsSleeveRetry() async throws {
        let (container, show) = try ListenTestData.make()
        let service = SleevePlaybackService()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in service }
        )
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        service.delaysPlayback = true
        room.playFromSleeve(album, songID: "a1")
        try await Task.sleep(for: .milliseconds(10))
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertTrue(
            room.isPlaying,
            "presentation may optimistically reflect the pending play command"
        )
        XCTAssertNil(
            room.sleevePlaybackSongID,
            "sleeve playback must wait for factual transport .playing"
        )
        XCTAssertFalse(
            room.isRecentDisc(album),
            "pending UI intent must never create durable recent-listening history"
        )
        service.failure = .songUnavailable("a1")
        room.tick()
        XCTAssertNotNil(room.playbackError)
        XCTAssertFalse(room.isRecentDisc(album))
        service.failure = nil
        service.delaysPlayback = false
        room.playFromSleeve(album, songID: "a2")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.sleevePlaybackSongID, "a2")
        room.stop()
    }

    func testFailedSleevePlaybackLeavesNoHistoryAndCanRetry() async throws {
        let (container, show) = try ListenTestData.make()
        let service = SleevePlaybackService()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in service }
        )
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        service.shouldFail = true
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.playbackError != nil && !room.busy }
        XCTAssertFalse(room.isRecentDisc(album))
        XCTAssertNil(room.sleevePlaybackSongID)
        service.shouldFail = false
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertTrue(room.isRecentDisc(album))
        XCTAssertEqual(room.sleevePlaybackSongID, "a1")
        room.stop()
    }

    func testSleeveSelectionKeepsPlayingWhenTabHides() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.playFromSleeve(album, songID: "a1")
        room.setActive(false)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.sleevePlaybackSongID, "a1")
        room.setActive(true)
        XCTAssertTrue(room.isPlaying)
        room.stop()
    }

    func testHeardMarksRequireActualEvidenceAndRecentMarksAreClearedWithShowData() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let record = SongFamiliarityRecord(songID: "a1", manualConfirmedAt: Date())
        context.insert(record)
        try context.save()
        let room = ListenTestData.room(context)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        XCTAssertFalse(room.containsHeardSongs(album))
        record.confirmActualListening(at: Date())
        try context.save()
        await room.load(show: show)
        XCTAssertTrue(room.containsHeardSongs(album))
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.stop()
        try ListeningShowDataCleaner.deleteShowScopedData(showID: show.id, in: context)
        try context.save()
        let reopened = ListenTestData.room(context)
        await reopened.load(show: show)
        XCTAssertFalse(reopened.isRecentDisc(album))
        XCTAssertTrue(reopened.containsHeardSongs(album))
    }

    func testInvalidSleeveSongDoesNotInterruptCurrentPlayback() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.playFromSleeve(album, songID: "missing")
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.track?.id, "a1")
        XCTAssertNil(room.sleevePlaybackSongID)
        XCTAssertNotNil(room.playbackError)
        room.stop()
    }

    func testSleeveSelectionClosesManuallyLoadedDiscBeforePlaying() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.restoreDisc(album)
        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertTrue(room.mechanism.isClosed)
        XCTAssertEqual(room.track?.id, "a1")
        room.stop()
    }

    func testRecentSleeveSurvivesRoomRecreationWithoutLoadingOrPlaying() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        XCTAssertFalse(room.isRecentDisc(album))
        room.browser.open(album)
        XCTAssertFalse(room.isRecentDisc(album))
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertTrue(room.isRecentDisc(album))
        room.stop()
        let reopened = ListenTestData.room(container.mainContext)
        await reopened.load(show: show)
        XCTAssertTrue(reopened.isRecentDisc(album))
        XCTAssertEqual(reopened.mechanism.disc?.id, album.id)
        XCTAssertNotNil(reopened.track)
        XCTAssertFalse(reopened.isPlaying)
    }

    func testSleeveSelectionPlaysChosenTrackAndPreservesPlayingPosition() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.track?.id, "a1")
        XCTAssertEqual(room.sleevePlaybackSongID, "a1")
        room.seek(23)
        let position = room.elapsed
        room.playFromSleeve(album, songID: "a1")
        XCTAssertEqual(room.elapsed, position)
        room.stop()
    }

    func testDefaultAllAndNoDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertEqual(room.browser.scope, .all)
        XCTAssertFalse(room.mechanism.hasDisc)
        XCTAssertNil(room.track)
        XCTAssertEqual(room.libraryDiscs, room.compilationDiscs)
        XCTAssertEqual(room.shelfDiscs, Array(room.compilationDiscs.prefix(ListeningDisplayProjector.Shelf.visibleCount)))
        XCTAssertTrue(room.shelfDiscs.allSatisfy { if case .compilation = $0.origin { true } else { false } })
    }

    func testBrowseAndDetailDoNotChangePlayingDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.loadDisc(album)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.seek(25)
        let state = room.playbackState
        let track = room.track
        room.selectScope(.artist("c"))
        room.browser.open(try XCTUnwrap(room.compilationDiscs.first))
        XCTAssertEqual(room.browser.scope, .artist("c"))
        XCTAssertNotNil(room.browser.detail)
        XCTAssertEqual(room.mechanism.disc, album)
        XCTAssertEqual(room.track, track)
        XCTAssertEqual(room.playbackState, state)
        XCTAssertFalse(room.isPlayingDisc(album))
        room.selectScope(.artist("a"))
        XCTAssertTrue(room.isPlayingDisc(album))
        room.stop()
    }

    func testShelfLimitAndFullLibraryAndNoPadding() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).first { $0.artistID == "a" })
        for index in 0..<6 {
            let id = "extra-\(index)"
            context.insert(CatalogAlbum(appleMusicAlbumID: id, title: id, artistIDs: ["a"], orderedTrackIDs: ["a1"]))
            snapshot.albumIDs.append(id)
        }
        try context.save()
        let room = ListenTestData.room(context)
        await room.load(show: show)
        room.selectScope(.artist("a"))
        XCTAssertEqual(room.libraryDiscs.count, 7)
        XCTAssertEqual(room.shelfDiscs.count, ListeningDisplayProjector.Shelf.visibleCount)
        XCTAssertTrue(room.display.showsAllDiscs)
        XCTAssertEqual(room.libraryDiscs.first?.id, "album")
        snapshot.albumIDs = Array(snapshot.albumIDs.prefix(2))
        try context.save()
        await room.load(show: show)
        XCTAssertEqual(room.libraryDiscs.count, 2)
        XCTAssertEqual(room.shelfDiscs.count, 2)
        XCTAssertFalse(room.display.showsAllDiscs)
        room.selectScope(.artist("c"))
        XCTAssertTrue(room.shelfDiscs.isEmpty)
        XCTAssertTrue(room.browseArtists.contains { $0.id == "c" })
    }

    func testStaleSelectionFallsBackToAll() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.selectScope(.artist("a"))
        show.artists.removeAll { $0.appleMusicArtistID == "a" }
        await room.load(show: show)
        XCTAssertEqual(room.browser.scope, .all)
    }

    func testStopResetsTrackAndRepeatedLoadPreservesPausedPosition() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.loadDisc(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.perform(.playPause)
        XCTAssertFalse(room.isPlaying, "Pause should be visible before the control action returns")
        XCTAssertEqual(room.display.player.phase, .paused)
        XCTAssertFalse(room.busy, "Synchronous pause must not enter the generic async busy state")
        room.seek(23)
        let state = room.playbackState
        room.loadDisc(album)
        XCTAssertEqual(room.trackIndex, 1)
        XCTAssertEqual(room.playbackState, state)
        room.stop()
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.trackIndex, 0)
        XCTAssertEqual(room.mechanism.disc, album)
        room.loadDisc(album)
        XCTAssertFalse(room.isPlaying)
        XCTAssertFalse(room.busy)
    }

    func testRefreshDoesNotReplaceLoadedCompilation() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.compilationDiscs.first)
        room.loadDisc(disc)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        let snapshot = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).first { $0.artistID == "a" })
        snapshot.topSongIDs = ["a1", "a2"]
        try container.mainContext.save()
        await room.load(show: show)
        XCTAssertEqual(room.mechanism.disc, disc)
        XCTAssertEqual(room.track?.id, "a2")
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.compilationDiscs.first?.tracks.map(\.id), ["a1", "a2"])
        room.stop()
    }

    func testCompilationUsesTwoSongsPerArtistPerDiscGroupedByArtist() {
        func track(_ id: String, _ duration: TimeInterval? = nil) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: duration))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [
            [track("a1"), track("a2"), track("a3"), track("a4"), track("a5"), track("a6"), track("a7")],
            [track("b1"), track("a2"), track("b3"), track("b4"), track("b5"), track("b6"), track("b7")]
        ])

        XCTAssertEqual(result.map { $0.tracks.map(\.id) }, [
            ["a1", "a2", "b1"],
            ["a3", "a4", "b3", "b4"],
            ["a5", "a6", "b5", "b6"],
            ["a7", "b7"]
        ])
        XCTAssertEqual(ListeningCompilationAssembler.tracksPerArtistPerDisc, 2)
        XCTAssertEqual(result.count, 4)
        XCTAssertLessThanOrEqual(result.count, ListeningCompilationAssembler.maxDiscCount)
    }

    func testCompilationGroupsMultipleArtistsConsecutivelyWithinDisc() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [
            [track("a1"), track("a2"), track("a3"), track("a4")],
            [track("b1"), track("b2"), track("b3"), track("b4")],
            [track("c1"), track("c2"), track("c3"), track("c4")]
        ])

        XCTAssertEqual(result.map { $0.tracks.map(\.id) }, [
            ["a1", "a2", "b1", "b2", "c1", "c2"],
            ["a3", "a4", "b3", "b4", "c3", "c4"]
        ])
    }

    func testCompilationGroupingIgnoresTrackDuration() {
        func track(_ id: String, _ duration: TimeInterval?) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: duration))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [[
            track("short", 1),
            track("very-long", 50_000),
            track("missing", nil),
            track("also-long", 90_000)
        ]])

        XCTAssertEqual(result.map { $0.tracks.map(\.id) }, [
            ["short", "very-long"],
            ["missing", "also-long"]
        ])
    }

    func testCompilationStopsAfterNineDiscs() {
        let tracks = (0..<80).map { index in
            ListeningDiscTrack(CatalogSong(
                appleMusicSongID: "\(index)",
                title: "Song \(index)",
                artistName: "Artist",
                duration: 300
            ))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(ListeningCompilationAssembler.maxDiscCount, 9)
        XCTAssertEqual(result.count, ListeningCompilationAssembler.maxDiscCount)
        XCTAssertEqual(result.map { $0.tracks.count }, Array(repeating: 2, count: 9))
        XCTAssertEqual(result.flatMap { $0.tracks }.map(\.id), (0..<18).map { String($0) })
    }

    func testConnectedArtistsAppearBeforeUnconnectedArtists() async throws {
        let (container, show) = try ListenTestData.make()
        // ListenTestData.make() sets show.artists: A (connected, slot 0), B (unconnected, slot 1), C (connected, slot 2)
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertEqual(room.browseArtists.map(\.name), ["A", "C", "B"])
        XCTAssertTrue(room.browseArtists[0].isConnected)
        XCTAssertTrue(room.browseArtists[1].isConnected)
        XCTAssertFalse(room.browseArtists[2].isConnected)
    }
}

@MainActor private final class SleevePlaybackService: ListeningPlaybackServicing {
    var shouldFail = false
    var delaysPlayback = false
    var failure: ListeningPlaybackError?
    private let player = ListeningFixturePlayer()
    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        try await player.prepare(items: items, source: source, startingAtSongID: startingAtSongID)
    }
    func play() async throws {
        if shouldFail { throw ListeningPlaybackError.songUnavailable("a1") }
        if delaysPlayback { return }
        try await player.play()
    }
    func pause() { player.pause() }
    func stop() { player.stop() }
    func seek(to time: TimeInterval) { player.seek(to: time) }
    func skipToNext() async throws { try await player.skipToNext() }
    func skipToPrevious() async throws { try await player.skipToPrevious() }
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? { player.snapshot(observedAt: observedAt) }
}
