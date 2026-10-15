import XCTest
import SwiftUI
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningLoadingTests: XCTestCase {
    func testCachedRecordsBecomePlayableBeforeArtistLookupFinishes() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: LoadingArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        let task = Task { await room.load(show: show) }
        defer { task.cancel(); room.stop(); room.mechanism.motion.stop() }
        try await wait { room.initialLoaded && room.accessResolved }
        XCTAssertEqual(room.access.authorizationStatus, .authorized)
        XCTAssertTrue(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
        XCTAssertNil(room.display.recoveryAction)
        let disc = try XCTUnwrap(room.discs.first)
        room.loadPlayableDisc(disc)
        try await ListenTestData.settle(room) { room.isPlaying }
        XCTAssertTrue(room.isPlaying, "Cached music must play while an unrelated artist is still matching")
    }

    func testRefreshKeepsResolvedPlaybackModeAndCachedDiscs() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let ids = room.discs.map(\.id)
        let refresh = Task { await room.load(show: show, force: true) }
        defer { refresh.cancel(); room.mechanism.motion.stop() }
        await Task.yield()
        XCTAssertTrue(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
        XCTAssertEqual(room.discs.map(\.id), ids)
        await refresh.value
    }

    func testLargeFestivalInitialLoadUsesRuntimeTopSongsWithoutEagerFullCatalog() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(20_000)
        let show = try Show(name: "Large Festival", date: start, startTime: start)
        show.artists = (0..<17).map {
            ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: "artist-\($0)")
        }
        context.insert(show)
        try context.save()

        let catalog = GatedLargeFestivalCatalog()
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        let load = Task { await room.load(show: show) }
        defer {
            load.cancel()
            catalog.releaseFullCatalog()
            room.mechanism.motion.stop()
        }

        try await wait {
            catalog.runtimeFetchCount == 17
                && !room.compilationDiscs.isEmpty
        }

        XCTAssertEqual(catalog.fullFetchCount, 0, "entering 听 must not eagerly fetch every artist's full catalog")
        XCTAssertEqual(catalog.featuredPlaylistFetchCount, 0)
        XCTAssertLessThanOrEqual(room.compilationDiscs.count, 3)

        await load.value

        let compilationTracks = room.compilationDiscs.flatMap(\.tracks)
        XCTAssertTrue((40...60).contains(compilationTracks.count), "large-festival compilation should stay within the bounded continuous-listening target")
        XCTAssertEqual(Set(compilationTracks.map(\.id)).count, compilationTracks.count)

        let countsByArtist = Dictionary(grouping: compilationTracks, by: \.artistName).mapValues(\.count)
        XCTAssertEqual(countsByArtist.count, 17, "coverage-first allocation should represent every artist")
        XCTAssertGreaterThanOrEqual(countsByArtist.values.min() ?? 0, 2)
        XCTAssertLessThanOrEqual((countsByArtist.values.max() ?? 0) - (countsByArtist.values.min() ?? 0), 1)

        let finalRead = ModelContext(container)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogSong>()), 0, "runtime top songs must remain memory-only")
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogAlbum>()), 0)
    }

    func testForceRefreshUpdatesCompilationFromRuntimeTopSongsWithoutReplacingCompleteSnapshot() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(20_000)
        let show = try Show(name: "Cached Festival", date: start, startTime: start)
        show.artists = (0..<3).map {
            ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: "artist-\($0)")
        }
        context.insert(show)

        for artistIndex in 0..<3 {
            let oldID = "old-\(artistIndex)"
            context.insert(CatalogSong(
                appleMusicSongID: oldID,
                title: "Old \(artistIndex)",
                artistName: "artist-\(artistIndex)",
                duration: 180
            ))
            context.insert(ArtistCatalogSnapshot(
                artistID: "artist-\(artistIndex)",
                artistName: "artist-\(artistIndex)",
                orderedSongIDs: [oldID],
                topSongIDs: [oldID],
                albumIDs: ["artist-\(artistIndex)-album-0", "artist-\(artistIndex)-album-1"],
                fetchedAt: Date()
            ))
            for albumIndex in 0..<2 {
                context.insert(CatalogAlbum(appleMusicAlbumID: "artist-\(artistIndex)-album-\(albumIndex)",
                    title: "Cached album", releaseDate: Date(), artistIDs: ["artist-\(artistIndex)"]))
            }
        }
        try context.save()

        let catalog = GatedLargeFestivalCatalog()
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer {
            catalog.releaseFullCatalog()
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show, force: true)

        XCTAssertEqual(catalog.runtimeFetchCount, 3)
        XCTAssertEqual(catalog.fullFetchCount, 0)
        XCTAssertEqual(
            Set(room.compilationDiscs.flatMap(\.tracks).map(\.id)),
            Set((0..<3).flatMap { artistIndex in
                (0..<10).map { "artist-\(artistIndex)-song-\($0)" }
            })
        )

        XCTAssertTrue(room.compilationDiscs.contains { $0.id.hasSuffix("-latest") && !$0.tracks.isEmpty },
                      "Runtime songs retain the release dates of already-cached albums")

        await room.reloadCatalog(force: true)
        XCTAssertEqual(catalog.runtimeFetchCount, 6, "repeated force refresh must bypass the in-memory runtime cache")
        XCTAssertEqual(catalog.fullFetchCount, 0)

        let read = ModelContext(container)
        let snapshots = try read.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(
            Set(snapshots.flatMap(\.topSongIDs)),
            Set(["old-0", "old-1", "old-2"]),
            "runtime topSongs must not rewrite the complete-catalog snapshot"
        )
        XCTAssertEqual(
            try read.fetchCount(FetchDescriptor<CatalogSong>()),
            3,
            "runtime topSongs must remain memory-only"
        )
    }

    func testSelectingArtistLoadsOnlyThatArtistsDetailedCatalog() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(20_000)
        let show = try Show(name: "Lazy Browse Festival", date: start, startTime: start)
        show.artists = (0..<17).map {
            ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: "artist-\($0)")
        }
        context.insert(show)
        try context.save()

        let catalog = GatedLargeFestivalCatalog()
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer {
            catalog.releaseFullCatalog()
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        XCTAssertEqual(catalog.fullFetchCount, 0)

        room.selectScope(.artist("artist-6"))
        try await wait { catalog.fullFetchCount == 1 }

        XCTAssertEqual(catalog.fullFetchArtistIDs, ["artist-6"])
        let whileBlocked = ModelContext(container)
        XCTAssertEqual(try whileBlocked.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)

        catalog.releaseFullCatalog()
        try await wait {
            room.browsingArtist?.id == "artist-6"
                && room.browsingArtist?.albums.count == 15
                && catalog.featuredPlaylistFetchCount == 1
        }

        let finalRead = ModelContext(container)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 1)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogSong>()), 100)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogAlbum>()), 15)
        XCTAssertEqual(catalog.fullFetchArtistIDs, ["artist-6"])
        XCTAssertEqual(catalog.featuredPlaylistFetchCount, 1)

        room.returnToWholeShow()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(catalog.fullFetchCount, 1, "returning to the compilation scope must not fetch other artists")
    }

    func testSelectingArtistDuringRuntimeRefreshLoadsThatArtistAfterRefresh() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(20_000)
        let show = try Show(name: "Scope Race Festival", date: start, startTime: start)
        show.artists = (0..<2).map {
            ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: "artist-\($0)")
        }
        context.insert(show)

        for artistIndex in 0..<2 {
            let songID = "cached-\(artistIndex)"
            context.insert(CatalogSong(
                appleMusicSongID: songID,
                title: "Cached \(artistIndex)",
                artistName: "artist-\(artistIndex)",
                duration: 180
            ))
            context.insert(ArtistCatalogSnapshot(
                artistID: "artist-\(artistIndex)",
                artistName: "artist-\(artistIndex)",
                orderedSongIDs: [songID],
                topSongIDs: [songID],
                albumIDs: [],
                fetchedAt: Date()
            ))
        }
        try context.save()

        let catalog = GatedLargeFestivalCatalog(gateRuntime: true)
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer {
            catalog.releaseRuntimeCatalog()
            catalog.releaseFullCatalog()
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        XCTAssertEqual(catalog.runtimeFetchCount, 0)

        let refresh = Task { await room.reloadCatalog(force: true) }
        try await wait { catalog.runtimeFetchCount == 2 }

        room.selectScope(.artist("artist-1"))
        XCTAssertEqual(catalog.fullFetchCount, 0, "selected artist should wait for the in-flight runtime refresh instead of starting a competing catalog generation")

        catalog.releaseRuntimeCatalog()
        try await wait { catalog.fullFetchCount == 1 }

        XCTAssertEqual(catalog.fullFetchArtistIDs, ["artist-1"])

        catalog.releaseFullCatalog()
        await refresh.value
        try await wait {
            room.browsingArtist?.id == "artist-1"
                && room.browsingArtist?.albums.count == 15
        }
    }

    func testCompilationPlaybackStaysWithinSelectedTheme() async throws {
        let (container, room, player, show) = try await makeFestivalRoom()
        _ = container
        let selected = try XCTUnwrap(room.compilationDiscs.dropFirst().first)
        let firstSongID = try XCTUnwrap(selected.tracks.first?.id)
        let lastSongID = try XCTUnwrap(selected.tracks.last?.id)
        room.restoreDisc(selected, songID: firstSongID)
        let window = try mountRoomView(room, show: show)
        defer { window.isHidden = true; room.stop(); room.mechanism.motion.stop() }
        let view = try XCTUnwrap(window.rootViewController?.view)
        try await settleLayout(view)

        room.skip(-1)
        try await settleLayout(view)

        XCTAssertEqual(room.mechanism.disc?.id, selected.id)
        XCTAssertEqual(room.track?.id, firstSongID, "Previous must not enter another theme")
        XCTAssertFalse(room.wantsPlayback)

        room.playFromSleeve(selected, songID: lastSongID)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(player.loadedSongIDs, selected.tracks.map(\.id), "only the seated theme belongs in the playback queue")
        XCTAssertEqual(player.loadedStartSongID, lastSongID)

        room.skip(1)
        try await settleLayout(view)
        XCTAssertEqual(room.track?.id, lastSongID, "Next must not enter another theme")

        player.finishQueue()
        try await wait { !room.isPlaying }
        try await settleLayout(view)
        XCTAssertEqual(room.mechanism.disc?.id, selected.id)
        XCTAssertEqual(room.track?.id, firstSongID, "playing through the theme stops at its first track")
        XCTAssertEqual(player.loadCount, 1)
    }

    func testAlbumNextMovesInsideThePreparedQueue() async throws {
        let (container, room, player, _) = try await makeFestivalRoom()
        _ = container
        defer { room.stop(); room.mechanism.motion.stop() }
        let source = room.compilationDiscs[0]
        let album = ListeningDisc(id: "queue-album", title: "Album", artworkURL: nil, tracks: Array(source.tracks.prefix(4)))
        room.restoreDisc(album, songID: album.tracks[0].id)

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.skip(1)
        try await wait { player.currentSongID == album.tracks[1].id && room.isPlaying }
        XCTAssertEqual(room.track?.id, album.tracks[1].id)
        room.skip(1)
        try await wait { player.currentSongID == album.tracks[2].id && room.isPlaying }
        XCTAssertEqual(room.track?.id, album.tracks[2].id)

        XCTAssertEqual(player.loadCount, 1, "Next within the loaded album must not rebuild the queue")
        XCTAssertEqual(player.nativeSkips, [1, 1])
    }

    /// The compact player's control must read back on the tap, and stay usable
    /// while the source still loads the queue.
    func testMiniPlayerControlFlipsOnTapWhileTheQueueLoads() async throws {
        let (container, room, player, _) = try await makeFestivalRoom()
        _ = container
        defer { room.stop(); room.mechanism.motion.stop() }
        let disc = room.compilationDiscs[0]
        room.restoreDisc(disc)
        player.loadDelay = .milliseconds(300)

        room.perform(.playPause)

        XCTAssertTrue(room.display.player.showsPauseControl)
        XCTAssertTrue(room.display.player.canPlayPause)
        XCTAssertTrue(room.display.player.shouldRotateDisc)
        XCTAssertFalse(room.busy)

        room.perform(.playPause)
        XCTAssertFalse(room.display.player.showsPauseControl)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(room.isPlaying, "a pause during loading must cancel the start")
        XCTAssertEqual(player.playCount, 0)
    }

    private func makeFestivalRoom() async throws -> (ModelContainer, ListeningRoomCoordinator, ListeningTestPlayer, Show) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(20_000)
        let show = try Show(name: "Continuous Festival", date: start, startTime: start)
        show.artists = (0..<17).map {
            ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: "artist-\($0)")
        }
        context.insert(show)
        try context.save()
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: GatedLargeFestivalCatalog(),
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { _ in player }
        )
        await room.load(show: show)
        return (container, room, player, show)
    }

    private func mountRoomView(_ room: ListeningRoomCoordinator, show: Show) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: ListeningRoomView(room: room, show: show))
        window.makeKeyAndVisible()
        return window
    }

    func testRestoredCompilationKeepsSelectedSongWhenRefreshedVolumesOmitIt() async throws {
        let (container, show) = try ListenTestData.make()
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: EmptyArtistSearch(),
            playbackFactory: { _ in player }
        )
        defer { room.stop(); room.mechanism.motion.stop() }
        await room.load(show: show)
        let current = try XCTUnwrap(room.compilationDiscs.first)
        let sharedTrack = try XCTUnwrap(current.tracks.first)
        let retiredTrack = ListeningDiscTrack(CatalogSong(
            appleMusicSongID: "retired-top-song", title: "Retired", artistName: "Artist", duration: 180
        ))
        let restored = ListeningDisc(
            id: current.id, title: current.title, artworkURL: nil,
            tracks: [sharedTrack, retiredTrack], origin: current.origin
        )
        room.restoreDisc(restored, songID: retiredTrack.id)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(player.loadedSongIDs, restored.tracks.map(\.id))
        XCTAssertEqual(room.track?.id, retiredTrack.id)

        room.stop()
        room.skip(1)
        XCTAssertEqual(room.mechanism.disc?.tracks.map(\.id), restored.tracks.map(\.id))
        XCTAssertEqual(room.track?.id, retiredTrack.id, "stopped Next must retain the loaded version")
        room.skip(-1)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(player.loadedSongIDs, restored.tracks.map(\.id), "a shared selected song must not replace the loaded record with refreshed contents")
        XCTAssertEqual(room.track?.id, sharedTrack.id)
    }

    func testPlayerPositionAcrossColdLaunchAuthorizationAndCatalogArrival() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .authorizationFlow)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .authorizationFlow, pace: 0.2),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        let probe = ListeningLayoutProbe()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        func content(_ view: some View) -> AnyView {
            AnyView(view
                .transaction { $0.disablesAnimations = true }
                .onPreferenceChange(ListeningFramesKey.self) { probe.frames = $0 })
        }
        let host = UIHostingController(rootView: content(ListeningPreparingView(show: show)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer { window.isHidden = true; room.mechanism.motion.stop() }
        try await wait { host.view.layoutIfNeeded(); return probe.frames["stage"] != nil }
        let coldStage = try XCTUnwrap(probe.frames["stage"])
        let coldCabinet = try XCTUnwrap(probe.frames["cabinet"])

        await room.load(show: show)
        XCTAssertEqual(room.presentation, .needsAuthorization)
        host.rootView = content(ListeningRoomView(room: room, show: show))
        try await settleLayout(host.view)
        assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)

        let authorization = Task { await room.authorize() }
        defer { authorization.cancel() }
        try await wait { room.isAuthorizing }
        try await settleLayout(host.view)
        XCTAssertEqual(room.display.roomMode, .connecting)
        XCTAssertNil(room.display.recoveryAction)
        assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)

        await authorization.value
        XCTAssertFalse(room.libraryDiscs.isEmpty)
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
        try await settleLayout(host.view)
        assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)
    }

    func testEmptyShelfStatusHeightsMatchInAllSupportedLanguages() {
        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let bundle = Bundle(path: Bundle.main.path(forResource: locale, ofType: "lproj")!)!
            func text(_ key: String, table: String? = nil) -> String { bundle.localizedString(forKey: key, value: key, table: table) }
            let variants = [
                ListeningCatalogStatusView(title: "Connecting…", isLoading: true),
                ListeningCatalogStatusView(title: text("连接 Apple Music"), subtitle: text("授权后载入唱片", table: "Listening"), actionTitle: "Authorize now"),
                ListeningCatalogStatusView(title: text("连接 Apple Music"), subtitle: text("请在系统设置中允许访问 Apple Music"), actionTitle: "Open Settings"),
                ListeningCatalogStatusView(title: text("正在检索与整理专场唱片…"), isLoading: true),
                ListeningCatalogStatusView(title: text("暂时无法载入音乐"), actionTitle: "Retry")
            ]
            let heights = variants.map { status in
                let host = UIHostingController(rootView: ListeningShelfView(title: "Popular Mix", count: "0") {
                    status
                })
                return host.sizeThatFits(in: CGSize(width: 362, height: 1000)).height
            }
            XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1, "\(locale): \(heights)")
        }
    }

    func testShelfHeightDoesNotChangeWhenShowAllActionAppears() {
        func height(showsAllDiscs: Bool) -> CGFloat {
            let host = UIHostingController(rootView: ListeningShelfView(
                title: nil,
                count: "1 张唱片",
                showsAllDiscs: showsAllDiscs,
                showAll: {}
            ) {
                Color.clear
            })
            return host.sizeThatFits(in: CGSize(width: 362, height: 1000)).height
        }

        XCTAssertEqual(height(showsAllDiscs: false), height(showsAllDiscs: true), accuracy: 1)
    }

    func testSelectingAndPlayingDiscsKeepsThePlayerAndShelfInPlace() async throws {
        for scenario in [ListeningFixtureScenario.singleFull, .manyDiscs] {
            let fixture = try ListeningDebugFixtures(scenario: scenario)
            let context = fixture.container.mainContext
            let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
            let room = ListeningRoomCoordinator(
                context: context,
                catalogService: ListeningFixtureCatalog(scenario: scenario),
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { ListeningFixturePlayer(source: $0) }
            )
            await room.load(show: show)
            let probe = ListeningLayoutProbe()
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            let host = UIHostingController(rootView: ListeningRoomView(room: room, show: show)
                .onPreferenceChange(ListeningFramesKey.self) { probe.frames = $0 })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; room.stop(); room.mechanism.motion.stop() }
            try await settleLayout(host.view)
            let stage = try XCTUnwrap(probe.frames["stage"])
            let cabinet = try XCTUnwrap(probe.frames["cabinet"])
            let disc = try XCTUnwrap(room.shelfDiscs.last)

            room.loadPlayableDisc(disc)
            for _ in 0..<300 {
                if room.isPlaying { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(room.isPlaying)
            try await settleLayout(host.view)
            assertFrames(probe.frames, stage: stage, cabinet: cabinet)

            room.perform(.playPause)
            try await wait { !room.isPlaying }
            try await settleLayout(host.view)
            XCTAssertEqual(room.display.player.phase, .paused)
            assertFrames(probe.frames, stage: stage, cabinet: cabinet)
        }
    }

    private func assertFrames(_ frames: [String: CGRect], stage: CGRect, cabinet: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frames["stage"]?.minY ?? -1, stage.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frames["cabinet"]?.height ?? -1, cabinet.height, accuracy: 1, file: file, line: line)
    }

    private func settleLayout(_ view: UIView) async throws {
        for _ in 0..<8 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Loading state did not arrive")
    }
}

@MainActor
private final class ListeningLayoutProbe {
    var frames: [String: CGRect] = [:]
}

private struct LoadingArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        try await Task.sleep(for: .seconds(5))
        return []
    }
}

private struct EmptyArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] { [] }
}

private final class GatedLargeFestivalCatalog: ListeningMusicCatalogServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let gateRuntime: Bool
    private var runtimeCatalogReleased = false
    private var runtimeCatalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var fullCatalogReleased = false
    private var fullCatalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var storedRuntimeFetchCount = 0
    private var storedFullFetchCount = 0
    private var storedFullFetchArtistIDs: [String] = []
    private var storedFeaturedPlaylistFetchCount = 0

    var runtimeFetchCount: Int { lock.withLock { storedRuntimeFetchCount } }
    var fullFetchCount: Int { lock.withLock { storedFullFetchCount } }
    var fullFetchArtistIDs: [String] { lock.withLock { storedFullFetchArtistIDs } }
    var featuredPlaylistFetchCount: Int { lock.withLock { storedFeaturedPlaylistFetchCount } }

    init(gateRuntime: Bool = false) {
        self.gateRuntime = gateRuntime
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        lock.withLock { storedRuntimeFetchCount += 1 }
        if gateRuntime {
            await waitForRuntimeCatalogRelease()
        }
        return Array(Self.payload(artistID: artistID, fetchedAt: Date()).songs.prefix(10))
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        lock.withLock {
            storedFullFetchCount += 1
            storedFullFetchArtistIDs.append(artistID)
        }
        await waitForFullCatalogRelease()
        return Self.payload(artistID: artistID, fetchedAt: fetchedAt)
    }

    func fetchFeaturedPlaylists(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningFeaturedPlaylistsPayload {
        lock.withLock { storedFeaturedPlaylistFetchCount += 1 }
        return ListeningFeaturedPlaylistsPayload(
            artistID: artistID,
            playlists: [],
            songs: [],
            fetchedAt: fetchedAt
        )
    }

    func releaseRuntimeCatalog() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard !runtimeCatalogReleased else { return [] }
            runtimeCatalogReleased = true
            defer { runtimeCatalogWaiters.removeAll() }
            return runtimeCatalogWaiters
        }
        waiters.forEach { $0.resume() }
    }

    private func waitForRuntimeCatalogRelease() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                if runtimeCatalogReleased { return true }
                runtimeCatalogWaiters.append(continuation)
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func releaseFullCatalog() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard !fullCatalogReleased else { return [] }
            fullCatalogReleased = true
            defer { fullCatalogWaiters.removeAll() }
            return fullCatalogWaiters
        }
        waiters.forEach { $0.resume() }
    }

    private func waitForFullCatalogRelease() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                if fullCatalogReleased { return true }
                fullCatalogWaiters.append(continuation)
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    private static func payload(
        artistID: String,
        fetchedAt: Date
    ) -> ListeningArtistCatalogPayload {
        let songIDs = (0..<100).map { "\(artistID)-song-\($0)" }
        let songs = songIDs.enumerated().map { offset, songID in
            ListeningCatalogSongPayload(
                songID: songID,
                title: "Song \(offset)",
                artistName: artistID,
                albumID: "\(artistID)-album-\(min(offset / 7, 14))",
                albumTitle: "Album \(min(offset / 7, 14))",
                artworkURL: nil,
                duration: 180,
                performerArtistIDs: [artistID],
                performerArtistNames: [artistID],
                previewURL: nil
            )
        }
        let albums = (0..<15).map { albumIndex in
            let lower = albumIndex * 7
            let upper = min(lower + 7, songIDs.count)
            let tracks = lower < upper ? Array(songIDs[lower..<upper]) : []
            return ListeningCatalogAlbumPayload(
                albumID: "\(artistID)-album-\(albumIndex)",
                title: "Album \(albumIndex)",
                artworkURL: nil,
                releaseDate: nil,
                artistIDs: [artistID],
                orderedTrackIDs: tracks
            )
        }
        return ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: artistID,
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: songIDs,
            topSongIDs: Array(songIDs.prefix(10)),
            albumIDs: albums.map(\.albumID),
            songs: songs,
            albums: albums,
            fetchedAt: fetchedAt
        )
    }
}
