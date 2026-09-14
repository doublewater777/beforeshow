import XCTest
import SwiftUI
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningLoadingTests: XCTestCase {
    func testKnownAuthorizationIsPublishedBeforeArtistLookupFinishes() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: LoadingArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        let task = Task { await room.load(show: show) }
        defer { task.cancel(); room.mechanism.motion.stop() }
        try await wait { room.initialLoaded }
        XCTAssertEqual(room.access.authorizationStatus, .authorized)
        XCTAssertFalse(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .connecting)
        XCTAssertNil(room.display.recoveryAction)
        XCTAssertFalse(room.discs.isEmpty, "Cached records should remain browsable during access lookup")
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

    func testLargeFestivalPublishesRuntimeCompilationBeforeFullCatalogAndPersistsOneCompleteBatch() async throws {
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
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        let load = Task { await room.load(show: show) }
        defer {
            load.cancel()
            catalog.releaseFullCatalog()
            room.mechanism.motion.stop()
        }

        try await wait {
            catalog.runtimeFetchCount == 17
                && catalog.fullFetchCount > 0
                && !room.compilationDiscs.isEmpty
        }

        XCTAssertEqual(catalog.featuredPlaylistFetchCount, 0)
        XCTAssertFalse(room.compilationDiscs.isEmpty, "BeforeShow compilation should be usable before full enrichment finishes")
        let preCoreRead = ModelContext(container)
        XCTAssertEqual(try preCoreRead.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)
        XCTAssertEqual(try preCoreRead.fetchCount(FetchDescriptor<CatalogSong>()), 0, "runtime top songs must remain memory-only")

        catalog.releaseFullCatalog()
        await load.value

        let finalRead = ModelContext(container)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 17)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogSong>()), 1_700)
        XCTAssertEqual(try finalRead.fetchCount(FetchDescriptor<CatalogAlbum>()), 255)
        XCTAssertEqual(catalog.featuredPlaylistFetchCount, 0, "initial load must not request browse-only playlists")
    }

    func testPlayerPositionAcrossColdLaunchAuthorizationAndCatalogArrival() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let fixture = try ListeningDebugFixtures(scenario: .authorizationFlow)
            let context = fixture.container.mainContext
            let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
            let room = ListeningRoomCoordinator(
                context: context,
                catalogService: ListeningFixtureCatalog(scenario: .authorizationFlow),
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { _ in ListeningFixturePlayer() }
            )
            let probe = ListeningLayoutProbe()
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            func content(_ view: some View) -> AnyView {
                AnyView(view.environment(\.dynamicTypeSize, size)
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
    }

    func testEmptyShelfStatusHeightsMatchInAllSupportedLanguages() {
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
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
                    }.environment(\.dynamicTypeSize, size))
                    return host.sizeThatFits(in: CGSize(width: 362, height: 1000)).height
                }
                XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1, "\(locale), \(size): \(heights)")
            }
        }
    }

    func testCabinetKeepsTheActiveTouchViewUntilTheLongPressDragEnds() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .singleFull)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        await room.load(show: show)
        room.selectScope(.artist("fixture-artist-0"))
        let disc = try XCTUnwrap(room.shelfDiscs.first)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: ListeningCabinetView(
            room: room, scale: 1, showAll: {}, showDetails: { _ in }
        ) { Color.clear })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; room.mechanism.motion.stop() }
        try await settleLayout(host.view)
        let longPress = try XCTUnwrap(cabinetLongPress(in: host.view))
        let touchView = try XCTUnwrap(longPress.view)
        XCTAssertEqual(longPress.minimumPressDuration, 0.30, accuracy: 0.001)
        XCTAssertTrue(touchView.window === window)

        XCTAssertTrue(room.beginPlayableDiscDrag(disc))
        try await settleLayout(host.view)

        XCTAssertTrue(room.mechanism.isCabinetDragging)
        XCTAssertTrue(touchView.window === window, "Picking up the CD must not remove the view receiving the active touch")
        XCTAssertTrue(cabinetLongPress(in: host.view) === longPress, "The same recognizer must receive the rest of the drag")
        let center = room.mechanism.configuration.geometry.discCenter
        room.mechanism.dragDisc(CGSize(width: center.x - room.mechanism.motion.discX.value,
                                      height: center.y - room.mechanism.motion.discY.value))
        room.mechanism.endDiscDrag()
        for _ in 0..<20 {
            let motion = room.mechanism.motion
            motion.lid.step(1); motion.discX.step(1); motion.discY.step(1)
            motion.lift.step(1); motion.discScale.step(1)
            room.mechanism.refresh()
        }
        XCTAssertEqual(room.mechanism.position, .seated)
        XCTAssertFalse(room.mechanism.isCabinetDragging)
        try await settleLayout(host.view)
        XCTAssertNil(touchView.window)
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
                playbackFactory: { _ in ListeningFixturePlayer() }
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

    private func cabinetLongPress(in view: UIView) -> UILongPressGestureRecognizer? {
        if let longPress = view.gestureRecognizers?.compactMap({ $0 as? UILongPressGestureRecognizer }).first {
            return longPress
        }
        return view.subviews.lazy.compactMap { self.cabinetLongPress(in: $0) }.first
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
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        try await Task.sleep(for: .seconds(5))
        return []
    }
}

private struct EmptyArtistSearch: ArtistSearchServicing {
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] { [] }
}

private final class GatedLargeFestivalCatalog: ListeningMusicCatalogServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var fullCatalogReleased = false
    private var fullCatalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var storedRuntimeFetchCount = 0
    private var storedFullFetchCount = 0
    private var storedFeaturedPlaylistFetchCount = 0

    var runtimeFetchCount: Int { lock.withLock { storedRuntimeFetchCount } }
    var fullFetchCount: Int { lock.withLock { storedFullFetchCount } }
    var featuredPlaylistFetchCount: Int { lock.withLock { storedFeaturedPlaylistFetchCount } }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        lock.withLock { storedRuntimeFetchCount += 1 }
        return Array(Self.payload(artistID: artistID, fetchedAt: Date()).songs.prefix(10))
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        lock.withLock { storedFullFetchCount += 1 }
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
