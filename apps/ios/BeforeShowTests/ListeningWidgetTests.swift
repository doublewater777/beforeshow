import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class ListeningWidgetTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("listening-widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = tempDirectory
    }

    override func tearDownWithError() throws {
        WidgetSnapshotStore.overrideContainerURL = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testListeningSnapshotCodableRoundTrip() throws {
        let original = WidgetListeningSnapshot(
            showID: UUID(),
            showName: "夜航西飞巡演",
            artistName: "回春丹",
            discTitle: "热门合辑 01",
            trackTitle: "艾蜜莉",
            coverImageURL: "https://example.com/cover.jpg",
            trackCount: 12,
            phase: .playing,
            control: .pause,
            hasSession: true,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetListeningSnapshot.self, from: data)

        XCTAssertEqual(original.showID, decoded.showID)
        XCTAssertEqual(original.showName, decoded.showName)
        XCTAssertEqual(original.artistName, decoded.artistName)
        XCTAssertEqual(original.discTitle, decoded.discTitle)
        XCTAssertEqual(original.trackTitle, decoded.trackTitle)
        XCTAssertEqual(original.coverImageURL, decoded.coverImageURL)
        XCTAssertEqual(original.trackCount, decoded.trackCount)
        XCTAssertEqual(original.phase, decoded.phase)
        XCTAssertEqual(original.control, decoded.control)
        XCTAssertEqual(original.hasSession, decoded.hasSession)
        XCTAssertTrue(original.isContentEqual(to: decoded))
    }

    func testListeningSnapshotContentEqualityIgnoresGeneratedAt() {
        let baseID = UUID()
        let snap1 = WidgetListeningSnapshot(
            showID: baseID,
            showName: "测试演出",
            artistName: "艺人A",
            discTitle: "合辑 01",
            trackTitle: "歌曲 1",
            coverImageURL: nil,
            trackCount: 10,
            phase: .paused,
            control: .play,
            hasSession: true,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let snap2 = WidgetListeningSnapshot(
            showID: baseID,
            showName: "测试演出",
            artistName: "艺人A",
            discTitle: "合辑 01",
            trackTitle: "歌曲 1",
            coverImageURL: nil,
            trackCount: 10,
            phase: .paused,
            control: .play,
            hasSession: true,
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertTrue(snap1.isContentEqual(to: snap2))

        var snap3 = snap2
        snap3.phase = .playing
        XCTAssertFalse(snap1.isContentEqual(to: snap3))
    }

    func testWidgetListeningStoreWriteReadAndClear() {
        XCTAssertNil(WidgetListeningStore.read())

        let snapshot = WidgetListeningSnapshot(
            showID: UUID(),
            showName: "草莓音乐节",
            artistName: "万能青年旅店",
            discTitle: "冀西南林路行",
            trackTitle: "山雀",
            coverImageURL: nil,
            trackCount: 8,
            phase: .idle,
            control: .play,
            hasSession: false,
            generatedAt: Date()
        )

        XCTAssertTrue(WidgetListeningStore.write(snapshot))
        let readBack = WidgetListeningStore.read()
        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack?.showName, "草莓音乐节")
        XCTAssertEqual(readBack?.trackTitle, "山雀")

        XCTAssertTrue(WidgetListeningStore.write(nil))
        XCTAssertNil(WidgetListeningStore.read())
    }

    func testWidgetListeningStoreFallbackFromShowSnapshot() throws {
        // 当尚无听歌快照但存在当前现场快照时，应自动降级生成现场预习快照
        let timing = ShowTimingFields(
            date: Date(),
            startTime: Date(),
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let showSnapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "安溥「炼云」演唱会",
            city: "台北",
            venueName: "小巨蛋",
            coverImageURL: "https://example.com/anpu.jpg",
            timing: timing,
            generatedAt: Date()
        )
        WidgetSnapshotStore.write(showSnapshot)

        let fallback = WidgetListeningStore.read()
        XCTAssertNotNil(fallback)
        XCTAssertEqual(fallback?.showID, showSnapshot.showID)
        XCTAssertEqual(fallback?.showName, "安溥「炼云」演唱会")
        XCTAssertNil(fallback?.coverImageURL, "现场海报留给倒计时小组件")
        XCTAssertEqual(fallback?.control, .openListen)
        XCTAssertEqual(fallback?.phase, .unavailable)
        XCTAssertFalse(fallback?.hasSession ?? true)
    }

    func testLegacyPlayingSnapshotDecodesAsSession() throws {
        struct Legacy: Encodable {
            var showName: String
            var isPlaying: Bool
            var generatedAt: Date
        }
        let url = try XCTUnwrap(WidgetListeningStore.snapshotURL)
        let data = try JSONEncoder().encode(
            Legacy(showName: "旧快照", isPlaying: true, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        )
        try data.write(to: url)
        let decoded = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(decoded.phase, .playing)
        XCTAssertEqual(decoded.control, .pause)
        XCTAssertTrue(decoded.hasSession)
    }

    @MainActor
    func testListeningIntentBridgeInvocation() async throws {
        final class MockIntentHandler: ListeningIntentHandling {
            var commands: [ListeningWidgetCommand] = []

            func perform(_ command: ListeningWidgetCommand) async { commands.append(command) }
        }

        let mock = MockIntentHandler()
        ListeningIntentBridge.handler = mock
        defer { ListeningIntentBridge.handler = nil }

        await ListeningIntentBridge.perform(.pause)
        XCTAssertEqual(mock.commands, [.pause])
    }


    func testListeningWidgetKindsRegistered() {
        XCTAssertTrue(BeforeShowWidgetKind.all.contains(BeforeShowWidgetKind.homeListening))
        XCTAssertEqual(BeforeShowWidgetKind.homeListening, "BeforeShowListeningWidget")
    }

    @MainActor
    func testSkippingInsideAppUpdatesWidgetTrack() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop(); room.mechanism.motion.stop() }
        await room.load(show: show)

        for disc in [room.compilationDiscs.first, room.browseArtists.first?.albums.first].compactMap({ $0 }) {
            guard disc.tracks.count >= 2 else { continue }
            room.restoreDisc(disc, songID: disc.tracks[0].id)
            room.playPause()
            try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
            XCTAssertEqual(WidgetListeningStore.read()?.trackTitle, disc.tracks[0].title)

            room.skip(1)
            let next = disc.tracks[1]
            try await ListenTestData.settle(room) { room.track?.id == next.id && room.isPlaying && !room.busy }
            XCTAssertEqual(WidgetListeningStore.read()?.trackTitle, next.title, "disc \(disc.title)")
            XCTAssertEqual(WidgetListeningStore.read()?.coverImageURL, disc.artworkURL?.absoluteString)
            room.stop()
        }
    }

    func testProjectionUsesDiscCoverWhilePreparing() {
        let record = makeDisc(trackArtwork: "https://example.invalid/track.jpg")
        let snapshot = WidgetListeningProjection.make(input(
            seated: record,
            phase: .preparing,
            action: .pause
        ))
        XCTAssertEqual(snapshot.coverImageURL, "https://example.invalid/disc.jpg")
        XCTAssertEqual(snapshot.trackTitle, "Track")
        XCTAssertEqual(snapshot.phase, .preparing)
        XCTAssertFalse(snapshot.phase.showsSoundingChrome)
        XCTAssertEqual(snapshot.control, .pause)
        XCTAssertTrue(snapshot.hasSession)
    }

    func testProjectionOffersPlayAfterInterruptionAndNoButtonAfterFailure() {
        let record = makeDisc(trackArtwork: nil)
        let interrupted = WidgetListeningProjection.make(input(
            seated: record,
            phase: .interrupted,
            action: .play
        ))
        XCTAssertEqual(interrupted.phase, .interrupted)
        XCTAssertFalse(interrupted.phase.showsSoundingChrome)
        XCTAssertEqual(interrupted.control, .play)

        let failed = WidgetListeningProjection.make(input(
            seated: record,
            phase: .failed,
            action: .disabled
        ))
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.control, .openListen)
        XCTAssertFalse(failed.phase.showsSoundingChrome)
    }

    func testProjectionOffersLiveHeadOnlyWhenItCanLoad() {
        let head = makeDisc(trackArtwork: "https://example.invalid/track.jpg")
        let playable = WidgetListeningProjection.make(input(
            seated: nil,
            phase: .stopped,
            action: .disabled,
            idle: head,
            idleCanLoad: true
        ))
        XCTAssertEqual(playable.phase, .idle)
        XCTAssertEqual(playable.control, .play)
        XCTAssertNil(playable.trackTitle)
        XCTAssertEqual(playable.discTitle, "唱片")
        XCTAssertEqual(playable.coverImageURL, "https://example.invalid/disc.jpg")
        XCTAssertFalse(playable.hasSession)

        let blocked = WidgetListeningProjection.make(input(
            seated: nil,
            phase: .stopped,
            action: .disabled,
            idle: head,
            idleCanLoad: false
        ))
        XCTAssertEqual(blocked.control, .openListen)
        XCTAssertNil(blocked.discTitle)

        let loading = WidgetListeningProjection.make(input(
            seated: nil,
            phase: .stopped,
            action: .disabled,
            mechanicallyBusy: true,
            pending: head
        ))
        XCTAssertEqual(loading.phase, .preparing)
        XCTAssertEqual(loading.control, .openListen)
        XCTAssertTrue(loading.hasSession)
        XCTAssertEqual(loading.discTitle, "唱片")
    }

    @MainActor
    func testCurrentShowChangeKeepsSeatedSessionAndClearsIdleDisc() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let showA = try Show(name: "现场 A", date: now, startTime: now)
        let showB = try Show(name: "现场 B", date: now, startTime: now)
        context.insert(showA)
        context.insert(showB)
        try context.save()

        WidgetDataSync.sync(
            shows: [showA],
            manualSelection: CurrentShowSelection(selectedShowID: showA.id),
            now: now
        )
        WidgetListeningStore.write(sessionSnapshot(show: showA, now: now))
        WidgetDataSync.sync(
            shows: [showB],
            manualSelection: CurrentShowSelection(selectedShowID: showB.id),
            now: now.addingTimeInterval(60)
        )
        let kept = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(kept.discTitle, "正在听的唱片")
        XCTAssertEqual(kept.phase, .playing)
        XCTAssertEqual(kept.control, .pause)
        XCTAssertTrue(kept.hasSession)
        XCTAssertEqual(WidgetSnapshotStore.read()?.name, "现场 B")

        WidgetListeningStore.write(WidgetListeningSnapshot(
            showID: showA.id,
            showName: showA.name,
            artistName: nil,
            discTitle: "推荐唱片",
            trackTitle: nil,
            coverImageURL: nil,
            trackCount: 3,
            phase: .idle,
            control: .play,
            hasSession: false,
            generatedAt: now
        ))
        WidgetSnapshotStore.write(nil)
        WidgetDataSync.sync(
            shows: [showA],
            manualSelection: CurrentShowSelection(selectedShowID: showA.id),
            now: now.addingTimeInterval(120)
        )
        WidgetDataSync.sync(
            shows: [showB],
            manualSelection: CurrentShowSelection(selectedShowID: showB.id),
            now: now.addingTimeInterval(180)
        )
        let cleared = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(cleared.showID, showB.id)
        XCTAssertNil(cleared.discTitle)
        XCTAssertEqual(cleared.control, .openListen)
        XCTAssertFalse(cleared.hasSession)
    }

    @MainActor
    func testRepeatedPlayCommandDoesNotPause() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer {
            ListeningRoomSessionStore.shared.adopt(nil)
            room.stop()
            room.mechanism.motion.stop()
        }
        await room.load(show: show)
        ListeningRoomSessionStore.shared.adopt(room)

        async let first = ListeningIntentHandler.shared.perform(.play)
        async let second = ListeningIntentHandler.shared.perform(.play)
        _ = await (first, second)
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.mechanism.disc?.id, room.livePreviewDisc?.id)
        XCTAssertEqual(WidgetListeningStore.read()?.control, .pause)

        await ListeningIntentHandler.shared.perform(.play)
        XCTAssertTrue(room.isPlaying)
    }

    @MainActor
    func testPauseDuringDiscLoadDoesNotCancelPlayback() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer {
            ListeningRoomSessionStore.shared.adopt(nil)
            room.stop()
            room.mechanism.motion.stop()
        }
        await room.load(show: show)
        ListeningRoomSessionStore.shared.adopt(room)
        let disc = try XCTUnwrap(room.compilationDiscs.first)
        room.loadDisc(disc, autoplay: true)
        await ListeningIntentHandler.shared.perform(.pause)
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(WidgetListeningStore.read()?.control, .pause)
    }

    @MainActor
    func testIdleWidgetPublishesTheLivePreviewDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }
        await room.load(show: show)
        let head = try XCTUnwrap(room.livePreviewDisc)
        room.syncWidgetListeningState()
        let snapshot = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(snapshot.discTitle, head.title)
        XCTAssertNil(snapshot.trackTitle)
        XCTAssertEqual(snapshot.coverImageURL, head.artworkURL?.absoluteString)
        XCTAssertEqual(snapshot.control, .play)
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertFalse(snapshot.hasSession)
    }

    @MainActor
    func testSeatedWidgetCoverStaysOnTheDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }
        await room.load(show: show)
        let song = CatalogSong(
            appleMusicSongID: "sleeve-song",
            title: "袖套曲",
            artistName: "艺人",
            artworkURL: "https://example.invalid/track.jpg",
            duration: 180,
            previewURL: "https://example.invalid/sleeve.m4a"
        )
        let record = ListeningDisc(
            id: "sleeve",
            title: "唱片",
            artworkURL: URL(string: "https://example.invalid/disc.jpg"),
            tracks: [ListeningDiscTrack(song)],
            origin: .compilation(showID: show.id, number: 9)
        )
        room.restoreDisc(record, songID: song.appleMusicSongID)
        XCTAssertEqual(WidgetListeningStore.read()?.coverImageURL, "https://example.invalid/disc.jpg")
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        let snapshot = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(snapshot.coverImageURL, "https://example.invalid/disc.jpg")
        XCTAssertEqual(snapshot.trackTitle, "袖套曲")
        XCTAssertTrue(snapshot.phase.showsSoundingChrome)
        XCTAssertEqual(snapshot.control, .pause)
    }

    @MainActor
    func testSwitchingCurrentShowDropsThePreviousListeningSession() async throws {
        try await assertShowSwitchClearsListeningSession(playing: true)
        try await assertShowSwitchClearsListeningSession(playing: false)
    }

    @MainActor
    func testColdWidgetPlayStartsTheLivePreviewDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        context.insert(CurrentShowSelection(selectedShowID: show.id, isManual: true))
        try context.save()
        let room = try await performColdWidgetPlay(container: container)
        defer { stopWidgetRoom(room) }
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.show?.id, show.id)
        XCTAssertEqual(room.mechanism.disc?.id, room.livePreviewDisc?.id)
        XCTAssertEqual(WidgetListeningStore.read()?.showID, show.id)
        XCTAssertEqual(WidgetListeningStore.read()?.control, .pause)
    }

    @MainActor
    func testColdWidgetPlayDoesNotStartWithoutMusic() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "没有音乐", date: now, startTime: now)
        context.insert(show)
        context.insert(CurrentShowSelection(selectedShowID: show.id, isManual: true))
        try context.save()
        let room = try await performColdWidgetPlay(container: container)
        defer { stopWidgetRoom(room) }
        XCTAssertFalse(room.isPlaying)
        XCTAssertNil(room.mechanism.disc)
        let snapshot = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(snapshot.showID, show.id)
        XCTAssertEqual(snapshot.control, .openListen)
        XCTAssertFalse(snapshot.hasSession)
    }

    @MainActor
    private func assertShowSwitchClearsListeningSession(playing: Bool) async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let room = ListenTestData.room(context)
        defer { stopWidgetRoom(room) }
        await room.load(show: show)
        let disc = try XCTUnwrap(room.compilationDiscs.first)
        if playing {
            room.loadDisc(disc, autoplay: true)
            try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        } else {
            room.restoreDisc(disc)
        }
        XCTAssertEqual(WidgetListeningStore.read()?.hasSession, true)
        ListeningRoomSessionStore.shared.adopt(room)
        let next = try Show(name: "下一场", date: Date(), startTime: Date())
        context.insert(next)
        try context.save()

        let prepared = await ListeningChromeBootstrapper.prepare(
            show: next,
            context: context,
            catalogService: WidgetReviewCatalog(),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        XCTAssertNil(prepared)
        XCTAssertFalse(room.isPlaying)
        let snapshot = try XCTUnwrap(WidgetListeningStore.read())
        XCTAssertEqual(snapshot.showID, next.id)
        XCTAssertNil(snapshot.discTitle)
        XCTAssertEqual(snapshot.control, .openListen)
        XCTAssertFalse(snapshot.hasSession)
    }

    @MainActor
    private func performColdWidgetPlay(container: ModelContainer) async throws -> ListeningRoomCoordinator {
        ListeningRoomSessionStore.shared.adopt(nil)
        let handler = ListeningIntentHandler.shared
        handler.configure(with: container)
        handler.playbackDependencies = ListeningWidgetPlaybackDependencies(
            catalogService: WidgetReviewCatalog(),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer { handler.playbackDependencies = nil }
        await handler.perform(.play)
        return try XCTUnwrap(ListeningRoomSessionStore.shared.room)
    }

    @MainActor
    private func stopWidgetRoom(_ room: ListeningRoomCoordinator?) {
        room?.stop()
        room?.mechanism.motion.stop()
        ListeningRoomSessionStore.shared.adopt(nil)
    }

    private func makeDisc(trackArtwork: String?) -> ListeningDisc {
        let song = CatalogSong(
            appleMusicSongID: "projection-song",
            title: "Track",
            artistName: "Artist",
            artworkURL: trackArtwork,
            duration: 100
        )
        return ListeningDisc(
            id: "projection-disc",
            title: "唱片",
            artworkURL: URL(string: "https://example.invalid/disc.jpg"),
            tracks: [ListeningDiscTrack(song)],
            artistNames: ["Artist"]
        )
    }

    private func input(
        seated: ListeningDisc?,
        phase: ListeningPlayerPhase,
        action: ListeningPlayPauseAction,
        mechanicallyBusy: Bool = false,
        pending: ListeningDisc? = nil,
        idle: ListeningDisc? = nil,
        idleCanLoad: Bool = false
    ) -> WidgetListeningProjection.Input {
        .init(
            showID: nil,
            showName: "现场",
            seatedDisc: seated,
            track: seated?.tracks.first,
            playerPhase: phase,
            playPauseAction: action,
            mechanicallyBusy: mechanicallyBusy,
            pendingDisc: pending,
            idleDisc: idle,
            idleCanLoad: idleCanLoad
        )
    }

    private func sessionSnapshot(show: Show, now: Date) -> WidgetListeningSnapshot {
        WidgetListeningSnapshot(
            showID: show.id,
            showName: show.name,
            artistName: "艺人",
            discTitle: "正在听的唱片",
            trackTitle: "歌曲",
            coverImageURL: "https://example.invalid/session.jpg",
            trackCount: 4,
            phase: .playing,
            control: .pause,
            hasSession: true,
            generatedAt: now
        )
    }
}

private struct WidgetReviewCatalog: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}
