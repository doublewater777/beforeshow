import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningBrowseTests: XCTestCase {
    func testDelayedPlaybackFailureAllowsSleeveRetry() async throws {
        let (container, show) = try ListenTestData.make()
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in player }
        )
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.selectScope(.artist("a"))
        player.acknowledgesCommands = false
        room.playFromSleeve(album, songID: "a1")
        try await Task.sleep(for: .milliseconds(10))
        try await ListenTestData.settle(room) { !room.busy && room.deck.isQueueLoaded }
        XCTAssertFalse(
            room.isPlaying,
            "transport truth must remain non-playing until the player actually starts"
        )
        XCTAssertEqual(room.display.player.phase, .waiting)
        XCTAssertTrue(
            room.isPlayingDisc(album),
            "cabinet playback marking must follow the shared active presentation during waiting"
        )
        XCTAssertFalse(
            room.isRecentDisc(album),
            "pending UI intent must never create durable recent-listening history"
        )
        player.failure = .songUnavailable("a1")
        try await waitUntil { room.playbackError != nil }
        XCTAssertFalse(room.isRecentDisc(album))
        player.failure = nil
        player.acknowledgesCommands = true
        room.playFromSleeve(album, songID: "a2")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.track?.id, "a2")
        room.stop()
    }

    func testSkippingFromPlayingToUnavailablePreviewTerminatesContinuingIntent() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let songs = try context.fetch(FetchDescriptor<CatalogSong>())
        let playable = try XCTUnwrap(songs.first { $0.appleMusicSongID == "a2" })
        playable.previewURL = "https://example.invalid/a2.m4a"
        try context.save()

        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .previewOnly),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        await room.load(show: show)
        room.selectScope(.artist("a"))
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        XCTAssertEqual(album.tracks.map(\.id), ["a2", "a1"])
        XCTAssertTrue(room.trackPresentation(for: album.tracks[0]).isPlayable)
        XCTAssertFalse(room.trackPresentation(for: album.tracks[1]).isPlayable)

        room.loadDisc(album, songID: "a2")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        room.skip(1)
        await room.settlePendingOperation()

        XCTAssertEqual(room.track?.id, "a1")
        XCTAssertFalse(room.wantsPlayback)
        XCTAssertEqual(room.display.player.phase, .stopped)
        XCTAssertEqual(room.display.player.playPauseAction, .disabled)
        XCTAssertFalse(room.display.player.shouldRotateDisc)
        room.stop()
    }

    func testFailedSleevePlaybackLeavesNoHistoryAndCanRetry() async throws {
        let (container, show) = try ListenTestData.make()
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in player }
        )
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        player.playError = ListeningPlaybackError.songUnavailable("a1")
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.playbackError != nil && !room.busy }
        XCTAssertFalse(room.isRecentDisc(album))
        player.playError = nil
        room.playFromSleeve(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertTrue(room.isRecentDisc(album))
        XCTAssertEqual(room.track?.id, "a1")
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
        XCTAssertEqual(room.track?.id, "a1")
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
        try await Task.sleep(for: .milliseconds(200))
        let position = room.elapsed
        room.playFromSleeve(album, songID: "a1")
        XCTAssertEqual(room.elapsed, position, accuracy: 0.1, "choosing the playing song must not restart it")
        XCTAssertGreaterThan(position, 0)
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
        let phase = room.deck.phase
        let track = room.track
        room.selectScope(.artist("c"))
        room.browser.open(try XCTUnwrap(room.compilationDiscs.first))
        XCTAssertEqual(room.browser.scope, .artist("c"))
        XCTAssertNotNil(room.browser.detail)
        XCTAssertEqual(room.mechanism.disc, album)
        XCTAssertEqual(room.track, track)
        XCTAssertEqual(room.deck.phase, phase)
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
        let pausedAt = room.elapsed
        room.loadDisc(album)
        XCTAssertEqual(room.trackIndex, 1)
        XCTAssertEqual(room.display.player.phase, .paused)
        XCTAssertEqual(room.elapsed, pausedAt)
        room.stop()
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.trackIndex, 0)
        XCTAssertEqual(room.elapsed, 0)
        XCTAssertEqual(room.timeText, "00:00")
        XCTAssertEqual(room.mechanism.disc, album)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.trackIndex, 0)
        XCTAssertEqual(reopened.track?.id, album.tracks.first?.id)
        XCTAssertEqual(reopened.elapsed, 0)
        XCTAssertEqual(reopened.timeText, "00:00")
        reopened.mechanism.motion.stop()

        room.loadDisc(album)
        XCTAssertFalse(room.isPlaying)
        XCTAssertFalse(room.busy)
    }

    func testStopDuringPendingTrackImmediatelyRestoresFirstTrack() async throws {
        let (container, show) = try ListenTestData.make()
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in player }
        )
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        let firstSongID = try XCTUnwrap(album.tracks.first?.id)
        let targetSongID = try XCTUnwrap(album.tracks.last?.id)
        XCTAssertNotEqual(firstSongID, targetSongID)

        room.loadDisc(album, songID: firstSongID)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.playPause()
        room.skip(1)
        XCTAssertEqual(room.track?.id, targetSongID)

        player.loadDelay = .milliseconds(200)
        room.playPause()
        XCTAssertTrue(room.isPlayerDisplayPreparing)
        XCTAssertEqual(room.playerDisplayTrack?.id, targetSongID)

        room.stop()

        XCTAssertEqual(room.trackIndex, 0)
        XCTAssertEqual(room.playerDisplayTrack?.id, firstSongID)
        XCTAssertFalse(room.isPlayerDisplayPreparing)
        XCTAssertEqual(room.elapsed, 0)
        XCTAssertEqual(room.playerDisplayTimeText, "00:00")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(room.trackIndex, 0)
        XCTAssertEqual(room.playerDisplayTrack?.id, firstSongID)
        XCTAssertEqual(room.playerDisplayTimeText, "00:00")
        XCTAssertFalse(room.wantsPlayback)
    }

    func testPendingTrackSelectionImmediatelyDrivesPlayerDisplay() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.loadDisc(album, songID: "a1")
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        try await Task.sleep(for: .milliseconds(100))

        room.playFromSleeve(album, songID: "a2")

        XCTAssertEqual(room.playerDisplayTrack?.id, "a2")
        XCTAssertEqual(room.playerDisplayTrackIndex, album.tracks.firstIndex(where: { $0.id == "a2" }))
        XCTAssertTrue(room.isPlayerDisplayPreparing)
        XCTAssertEqual(room.playerDisplayTimeText, "00:00")

        try await ListenTestData.settle(room) { room.track?.id == "a2" && room.isPlaying && !room.busy }
        room.stop()
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

    func testCompilationUsesCoverageFirstSelectionAndGlobalDeduplication() {
        func track(_ id: String, artist: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: artist))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [
            ["a1", "a2", "a3", "a4", "a5", "a6", "a7"].map { track($0, artist: "A") },
            ["b1", "a2", "b3", "b4", "b5", "b6", "b7"].map { track($0, artist: "B") }
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tracks.map(\.id), [
            "a1", "a2", "a3", "a4", "a5", "a6", "a7",
            "b1", "b3", "b4", "b5", "b6", "b7"
        ])
        XCTAssertEqual(Set(result.flatMap(\.tracks).map(\.id)).count, 13)
    }

    func testCompilationGroupsMultipleArtistsConsecutivelyWithinDisc() {
        func tracks(_ prefix: String) -> [ListeningDiscTrack] {
            (1...4).map { index in
                .init(CatalogSong(
                    appleMusicSongID: "\(prefix.lowercased())\(index)",
                    title: "\(prefix) \(index)",
                    artistName: prefix
                ))
            }
        }

        let result = ListeningCompilationAssembler.discs(
            showID: UUID(),
            artistTracks: [tracks("A"), tracks("B"), tracks("C")]
        )

        XCTAssertEqual(result.map { $0.tracks.map(\.id) }, [[
            "a1", "a2", "a3", "a4",
            "b1", "b2", "b3", "b4",
            "c1", "c2", "c3", "c4"
        ]])
    }

    func testLargeFestivalCompilationCapsAtThreeTwentyTrackVolumesWithFairCoverage() {
        let artistTracks = (0..<25).map { artistIndex in
            (1...5).map { rank in
                ListeningDiscTrack(CatalogSong(
                    appleMusicSongID: "artist-\(artistIndex)-song-\(rank)",
                    title: "Song \(rank)",
                    artistName: "artist-\(artistIndex)"
                ))
            }
        }

        let result = ListeningCompilationAssembler.discs(
            showID: UUID(),
            artistTracks: artistTracks
        )
        let allTracks = result.flatMap(\.tracks)
        let counts = Dictionary(grouping: allTracks, by: \.artistName).mapValues(\.count)

        XCTAssertEqual(ListeningCompilationAssembler.maxDiscCount, 3)
        XCTAssertEqual(ListeningCompilationAssembler.maxTracksPerDisc, 20)
        XCTAssertEqual(ListeningCompilationAssembler.maxMultiArtistTrackCount, 60)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map { $0.tracks.count }, [20, 20, 20])
        XCTAssertEqual(allTracks.count, 60)
        XCTAssertEqual(Set(allTracks.map(\.id)).count, 60)
        XCTAssertEqual(counts.count, 25)
        XCTAssertEqual(counts.values.min(), 2)
        XCTAssertEqual(counts.values.max(), 3)

        for artistIndex in 0..<25 {
            let ids = allTracks
                .filter { $0.artistName == "artist-\(artistIndex)" }
                .map(\.id)
            XCTAssertEqual(
                ids,
                (1...ids.count).map { "artist-\(artistIndex)-song-\($0)" }
            )
        }
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
            ["short", "very-long", "missing", "also-long"]
        ])
    }

    func testSingleArtistCompilationPacksRichDiscsAndCapsAtThreeDiscs() {
        let tracks = (0..<80).map { index in
            ListeningDiscTrack(CatalogSong(
                appleMusicSongID: "\(index)",
                title: "Song \(index)",
                artistName: "Artist",
                duration: 300
            ))
        }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(ListeningCompilationAssembler.singleArtistMaxDiscCount, 3)
        XCTAssertEqual(ListeningCompilationAssembler.singleArtistTracksPerDisc, 10)
        XCTAssertEqual(result.count, ListeningCompilationAssembler.singleArtistMaxDiscCount)
        XCTAssertEqual(result.map { $0.tracks.count }, [10, 10, 10])
        XCTAssertEqual(result.flatMap { $0.tracks }.map(\.id), (0..<30).map { String($0) })
    }

    func testSingleArtistCompilationProducesSingleRichDisc() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let tracks = (0..<10).map { track("song-\($0)") }
        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tracks.count, 10)
        XCTAssertEqual(result.first?.tracks.map(\.id), (0..<10).map { "song-\($0)" })
        XCTAssertEqual(result.first?.title, BSLocalization.format("热门合辑 %02d", 1))
    }

    func testSingleArtistCompilationPartitionsIntoRichDiscs() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let tracks = (0..<25).map { track("song-\($0)") }
        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map { $0.tracks.count }, [10, 10, 5])
        XCTAssertEqual(result.map(\.title), [
            BSLocalization.format("热门合辑 %02d", 1),
            BSLocalization.format("热门合辑 %02d", 2),
            BSLocalization.format("热门合辑 %02d", 3)
        ])
    }

    func testSingleActiveArtistWithEmptyArtistSlotsUsesSingleArtistPacking() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let tracks = (0..<15).map { track("s-\($0)") }
        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks, [], []])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { $0.tracks.count }, [10, 5])
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
