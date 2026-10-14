import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningBrowseTests: XCTestCase {
    func testRackSwipeMatchesShelfMock() {
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 3, translation: -10, count: 15), 3)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 3, translation: -14, count: 15), 4)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 3, translation: 40, count: 15), 2)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 3, translation: -88, count: 15), 5)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 3, translation: -200, count: 15), 8)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 0, translation: 80, count: 15), 0)
        XCTAssertEqual(ListeningRackLayout.swipeIndex(from: 14, translation: -80, count: 15), 14)
    }

    func testRackPlateScrubMatchesShelfMock() {
        XCTAssertEqual(ListeningRackLayout.scrubIndex(from: 3, translation: 5, count: 15), 3)
        XCTAssertEqual(ListeningRackLayout.scrubIndex(from: 3, translation: 12, count: 15), 4)
        XCTAssertEqual(ListeningRackLayout.scrubIndex(from: 3, translation: -36, count: 15), 0)
        XCTAssertEqual(ListeningRackLayout.scrubIndex(from: 14, translation: 132, count: 15), 14)
    }

    func testRackTapLandsOnTheCaseUnderTheFinger() {
        let offset = { (x: CGFloat) in ListeningRackLayout.tapOffset(atX: x, focus: 3, count: 15, discOut: true, halfWidth: 195) }
        XCTAssertEqual(offset(0), 0)
        XCTAssertEqual(offset(-100), -1)
        XCTAssertEqual(offset(100), 1)
        XCTAssertEqual(offset(190), 3)
        XCTAssertEqual(ListeningRackLayout.tapOffset(atX: 160, focus: 0, count: 2, discOut: true, halfWidth: 195), 1)
    }

    func testCabinetSwapRequiresDroppingOnTheTray() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        defer { room.stop(); room.mechanism.motion.stop() }
        let current = try XCTUnwrap(room.discs.first)
        let replacement = try XCTUnwrap(room.browseArtists.first?.albums.first)
        XCTAssertNotEqual(current.id, replacement.id)
        room.restoreDisc(current)
        let geometry = room.hardwareGeometry
        let origin = CGPoint(x: 280, y: 100)
        let scale: CGFloat = 0.8
        room.mechanism.cabinetSlots[replacement.id] = origin

        for (drop, cancelled) in [(CGPoint(x: 800, y: geometry.discCenter.y), false),
                                  (CGPoint(x: geometry.discCenter.x, y: geometry.discCenter.y + 300), false),
                                  (origin, false),
                                  (geometry.discCenter, true)] {
            XCTAssertTrue(room.beginCabinetDragIfNeeded(replacement))
            room.updateCabinetDrag(of: replacement, translation: CGSize(
                width: (drop.x - origin.x) * scale,
                height: (drop.y - origin.y) * scale * cos(geometry.tiltDegrees * .pi / 180)
            ), scale: scale)
            room.endCabinetDrag(of: replacement, cancelled: cancelled)
            await room.settlePendingOperation()
            XCTAssertNil(room.pendingCabinetSwap)
            XCTAssertEqual(room.mechanism.disc?.id, current.id, "A missed drop must retain the loaded CD")
            XCTAssertFalse(room.isPlaying)
        }

        XCTAssertTrue(room.beginCabinetDragIfNeeded(replacement))
        room.updateCabinetDrag(of: replacement, translation: CGSize(
            width: (geometry.discCenter.x - origin.x) * scale,
            height: (geometry.discCenter.y - origin.y) * scale * cos(geometry.tiltDegrees * .pi / 180)
        ), scale: scale)
        room.endCabinetDrag(of: replacement)
        try await ListenTestData.settle(room) { !room.busy && room.isPlaying }
        XCTAssertNil(room.pendingCabinetSwap)
        XCTAssertEqual(room.mechanism.disc?.id, replacement.id)
    }

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

    func testFestivalCompilationSplitsIntoSingalongLatestAndDeepCuts() {
        let artistTracks = (0..<25).map { artistIndex in
            (1...5).map { rank in
                ListeningDiscTrack(CatalogSong(
                    appleMusicSongID: "artist-\(artistIndex)-song-\(rank)",
                    title: "Song \(rank)",
                    artistName: "artist-\(artistIndex)"
                ))
            }
        }
        let base = Date(timeIntervalSince1970: 0)
        let releaseDates = ["artist-3-song-5": base.addingTimeInterval(200), "artist-7-song-2": base.addingTimeInterval(100)]

        let result = ListeningCompilationAssembler.discs(showID: UUID(), releaseDates: releaseDates, artistTracks: artistTracks)

        XCTAssertEqual(result.map(\.title), [.singalong, .latest, .deepCuts].map { (theme: ListeningCompilationAssembler.Theme) in theme.title })
        XCTAssertEqual(result[0].tracks.map(\.id), (0..<20).map { "artist-\($0)-song-1" })
        XCTAssertEqual(result[1].tracks.map(\.id), ["artist-3-song-5", "artist-7-song-2"])
        XCTAssertEqual(result[2].tracks.count, 20)
        XCTAssertFalse(result[2].tracks.contains { $0.id == "artist-7-song-2" })
        XCTAssertEqual(Set(result.flatMap(\.tracks).map(\.id)).count, 42)
    }

    func testLiveProgramsLeadAndFillEachSetToItsLength() {
        func tracks(_ prefix: String) -> [ListeningDiscTrack] {
            (1...10).map { ListeningDiscTrack(CatalogSong(appleMusicSongID: "\(prefix)\($0)", title: "\($0)", artistName: prefix, duration: 240)) }
        }
        typealias Assembler = ListeningCompilationAssembler

        let showID = UUID()
        let result = Assembler.discs(
            showID: showID,
            livePrograms: [
                .init(key: "stage", title: "Day 1 · Main", sets: [.init(tracks: tracks("c"), duration: 900), .init(tracks: tracks("a"), duration: 1_300)]),
                .init(key: "wanted", title: "想看", sets: [])
            ],
            artistTracks: [tracks("a"), tracks("b"), tracks("c")]
        )

        XCTAssertEqual(result.first?.title, "Day 1 · Main")
        XCTAssertEqual(result.first?.tracks.map(\.id), ["c1", "c2", "c3", "c4", "a1", "a2", "a3", "a4", "a5"])
        XCTAssertEqual(result.dropFirst().first?.title, Assembler.Theme.singalong.title)
        XCTAssertEqual(result.map(\.origin), result.indices.map { .compilation(showID: showID, number: $0 + 1) })
    }

    func testRouteCutsEachSetWhenTheNextChosenSetStarts() {
        let base = Date(timeIntervalSince1970: 0)
        let sets = ListeningCompilationAssembler.route([
            (tracks: [], startsAt: base, endsAt: base.addingTimeInterval(3_600)),
            (tracks: [], startsAt: base.addingTimeInterval(2_400), endsAt: base.addingTimeInterval(5_400)),
            (tracks: [], startsAt: base.addingTimeInterval(5_400), endsAt: base.addingTimeInterval(6_000)),
            (tracks: [], startsAt: base.addingTimeInterval(5_400), endsAt: base.addingTimeInterval(7_000))
        ])

        XCTAssertEqual(sets.map(\.duration), [2_400, 3_000, 1_600])
    }

    func testCompilationSkipsLatestWithoutReleaseDates() {
        let tracks = (0..<80).map { ListeningDiscTrack(CatalogSong(appleMusicSongID: "\($0)", title: "\($0)", artistName: "Artist")) }

        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(result.map(\.title), [ListeningCompilationAssembler.Theme.singalong.title, ListeningCompilationAssembler.Theme.deepCuts.title])
        XCTAssertEqual(result.flatMap(\.tracks).map(\.id), (0..<20).map { String($0) })
        XCTAssertEqual(result.map(\.id).last?.hasSuffix("-deepCuts"), true)
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

    func testSingleArtistCompilationProducesSingleRichDisc() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let tracks = (0..<10).map { track("song-\($0)") }
        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tracks.count, 10)
        XCTAssertEqual(result.first?.tracks.map(\.id), (0..<10).map { "song-\($0)" })
        XCTAssertEqual(result.first?.title, ListeningCompilationAssembler.Theme.singalong.title)
    }

    func testSingleArtistCompilationPartitionsIntoRichDiscs() {
        func track(_ id: String) -> ListeningDiscTrack {
            .init(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist"))
        }

        let tracks = (0..<25).map { track("song-\($0)") }
        let result = ListeningCompilationAssembler.discs(showID: UUID(), artistTracks: [tracks])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { $0.tracks.count }, [10, 10])
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
