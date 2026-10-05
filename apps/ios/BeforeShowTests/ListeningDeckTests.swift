import AVFoundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningDeckTests: XCTestCase {
    // MARK: - Commands read back immediately

    func testPlayShowsPauseImmediatelyAndKeepsItWhileTheSourceLoads() async throws {
        let factory = PlayerFactory { $0.loadDelay = .milliseconds(300) }
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1", "a2"])], cursor: "a1")

        deck.play(source: .fullCatalog)

        XCTAssertEqual(deck.phase, .preparing)
        XCTAssertTrue(deck.wantsPlayback, "the control must flip on the tap, not after loading")
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(deck.phase, .playing)
        XCTAssertEqual(factory.last.loadCount, 1)
        XCTAssertEqual(factory.last.loadedStartSongID, "a1")
    }

    func testPauseWhileLoadingCancelsTheStart() async throws {
        let factory = PlayerFactory { $0.loadDelay = .milliseconds(200) }
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1")

        deck.play(source: .fullCatalog)
        deck.pause()

        XCTAssertFalse(deck.wantsPlayback)
        XCTAssertEqual(deck.phase, .stopped)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(factory.last.playCount, 0)
        XCTAssertFalse(deck.wantsPlayback)
    }

    func testPauseWinsOverAPlayStillReachingThePlayer() async throws {
        let factory = PlayerFactory { $0.playDelay = .milliseconds(200) }
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1")

        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isQueueLoaded }
        XCTAssertEqual(deck.phase, .waiting)
        deck.pause()
        XCTAssertFalse(deck.wantsPlayback)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(factory.last.phase, .paused, "a late Play must not resume after Pause")
        XCTAssertFalse(deck.wantsPlayback)
    }

    // MARK: - Navigation stays inside the loaded queue

    func testSelectingAnotherSongJumpsInsideTheLoadedQueue() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1", "a2", "a3"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        deck.select("a3", autoplay: true, source: .fullCatalog)

        XCTAssertEqual(deck.cursorSongID, "a3")
        XCTAssertTrue(deck.wantsPlayback)
        try await waitUntil { factory.last.jumps == ["a3"] && deck.isPlaying }
        XCTAssertEqual(factory.last.loadCount, 1, "selecting a song must not rebuild the queue")
    }

    func testNextWhilePlayingUsesTheQueueAndWhileStoppedMovesTheCursor() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1", "a2", "a3"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        deck.skip(by: 1, source: .fullCatalog)
        XCTAssertEqual(deck.cursorSongID, "a2")
        try await waitUntil { factory.last.nativeSkips == [1] }
        XCTAssertTrue(deck.isPlaying)
        XCTAssertEqual(factory.last.loadCount, 1)

        deck.pause()
        try await waitUntil { !deck.wantsPlayback }
        deck.skip(by: 1, source: .fullCatalog)
        XCTAssertEqual(deck.cursorSongID, "a3")
        XCTAssertFalse(deck.wantsPlayback)
        XCTAssertEqual(factory.last.loadCount, 1)

        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadCount, 2)
        XCTAssertEqual(factory.last.loadedStartSongID, "a3")
    }

    func testQuickRepeatedNextTapsAllLand() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1", "a2", "a3", "a4", "a5", "a6"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        for _ in 0..<4 {
            deck.skip(by: 1, source: .fullCatalog)
        }

        XCTAssertEqual(deck.cursorSongID, "a5")
        try await waitUntil { factory.last.currentSongID == "a5" && deck.isPlaying }
        XCTAssertEqual(deck.cursorSongID, "a5")
        XCTAssertEqual(factory.last.loadCount, 1)
    }

    func testCursorFollowsNaturalPlaybackAcrossCompilationVolumes() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        let showID = UUID()
        let first = compilation(showID, number: 1, songs: ["v1-1", "v1-2"])
        let second = compilation(showID, number: 2, songs: ["v2-1", "v2-2"])
        var cursorChanges: [String] = []
        deck.onCursorChange = { cursorChanges.append($0) }
        deck.load([first, second], cursor: "v1-2")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadedSongIDs, ["v1-1", "v1-2", "v2-1", "v2-2"])

        factory.last.advanceNaturally()

        try await waitUntil { deck.cursorSongID == "v2-1" }
        XCTAssertEqual(deck.currentDisc?.id, second.id)
        XCTAssertTrue(deck.wantsPlayback)
        XCTAssertEqual(cursorChanges, ["v2-1"])
        XCTAssertEqual(factory.last.loadCount, 1)
    }

    func testStopReturnsToTheFirstTrackOfTheVisibleVolume() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        let showID = UUID()
        let first = compilation(showID, number: 1, songs: ["v1-1", "v1-2"])
        let second = compilation(showID, number: 2, songs: ["v2-1", "v2-2"])
        deck.load([first, second], cursor: "v2-2")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        deck.stop()

        XCTAssertEqual(deck.cursorSongID, "v2-1")
        XCTAssertEqual(deck.phase, .stopped)
        XCTAssertEqual(deck.time, 0)
        XCTAssertEqual(factory.last.stopCount, 1)
    }

    // MARK: - The player is the source of truth

    func testExternalPauseAndResumeAreReadFromThePlayer() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.phase = .paused
        try await waitUntil { deck.phase == .paused }
        XCTAssertFalse(deck.wantsPlayback)

        factory.last.phase = .playing
        try await waitUntil { deck.phase == .playing }
        XCTAssertTrue(deck.wantsPlayback)
    }

    func testPauseDuringInterruptionOutlastsTheSystemResume() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        factory.last.phase = .interrupted
        try await waitUntil { deck.phase == .interrupted }

        factory.last.acknowledgesCommands = false
        deck.pause()
        XCTAssertEqual(deck.phase, .paused)
        factory.last.acknowledgesCommands = true

        factory.last.phase = .playing
        try await waitUntil { factory.last.phase == .paused }
        XCTAssertFalse(deck.wantsPlayback)
        XCTAssertEqual(deck.phase, .paused)
    }

    func testInterruptionEndingPausedDoesNotAutoplay() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.phase = .interrupted
        try await waitUntil { deck.phase == .interrupted }
        factory.last.phase = .paused
        try await waitUntil { deck.phase == .paused }

        XCTAssertFalse(deck.wantsPlayback)
        XCTAssertEqual(factory.last.playCount, 1)
    }

    func testFinishedQueueReloadsFromItsLastSongOnPlay() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1", "a2"])], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.finishQueue()
        try await waitUntil { deck.phase == .finished && deck.cursorSongID == "a2" }
        XCTAssertFalse(deck.wantsPlayback)

        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadCount, 2)
        XCTAssertEqual(factory.last.loadedStartSongID, "a2")
    }

    func testFailedStartIsReportedAndRetryReloads() async throws {
        let factory = PlayerFactory { $0.playError = ListeningPlaybackError.songUnavailable("a1") }
        let deck = ListeningDeck(makeEngine: factory.make)
        var failures = 0
        deck.onFailure = { failures += 1 }
        deck.load([album("a", songs: ["a1"])], cursor: "a1")

        deck.play(source: .fullCatalog)
        try await waitUntil { deck.phase == .failed }
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(deck.wantsPlayback)

        factory.last.playError = nil
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadCount, 2)
    }

    func testRestoredPositionOnlySeedsTheFirstStart() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"])], cursor: "a1", resumeAt: 42)
        XCTAssertEqual(deck.time, 42)

        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadedResumeTime, 42)

        deck.stop()
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        XCTAssertEqual(factory.last.loadedResumeTime, 0)
    }

    func testSwitchingSourceStopsThePreviousPlayer() async throws {
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.load([album("a", songs: ["a1"], preview: true)], cursor: "a1")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }
        let full = factory.last

        deck.play(source: .preview)
        try await waitUntil { deck.isPlaying && deck.source == .preview }
        XCTAssertEqual(factory.created.count, 2)
        XCTAssertEqual(full.stopCount, 1)
    }

    // MARK: - Listening evidence

    func testFullPlaybackPastHalfConfirmsActualListening() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext)
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.evidenceProvider = { evidence }
        var committed: [String] = []
        deck.onEvidence = { result, _ in committed += result.committedSongIDs }
        deck.load([album("a", songs: ["short"], duration: 2)], cursor: "short")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.currentTime = 1.2
        deck.pause()

        XCTAssertEqual(committed, ["short"])
        let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SongFamiliarityRecord>()).first)
        XCTAssertEqual(record.songID, "short")
        XCTAssertNotNil(record.actualListeningAt)
    }

    func testPreviewPlaybackNeverConfirmsActualListening() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext)
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.evidenceProvider = { evidence }
        deck.load([album("a", songs: ["clip"], duration: 2, preview: true)], cursor: "clip")
        deck.play(source: .preview)
        try await waitUntil { deck.isPlaying }

        factory.last.currentTime = 1.8
        deck.pause()

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
    }

    func testStopDrainsListeningEvidenceBeforeUnloading() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext)
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.evidenceProvider = { evidence }
        deck.load([album("a", songs: ["short"], duration: 2)], cursor: "short")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.currentTime = 1.2
        deck.stop()

        XCTAssertNotNil(try container.mainContext.fetch(FetchDescriptor<SongFamiliarityRecord>()).first?.actualListeningAt)
    }

    func testEvidenceFailureIsReportedAndCommitsOnALaterFlush() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        var persistenceAvailable = false
        let evidence = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context).confirmActualFamiliarity(songID: songID, at: date)
                guard persistenceAvailable else { throw DeckTestError.persistence }
                try context.save()
            }
        )
        let factory = PlayerFactory()
        let deck = ListeningDeck(makeEngine: factory.make)
        deck.evidenceProvider = { evidence }
        var failures = 0
        deck.onEvidence = { result, _ in if result.hasFailure { failures += 1 } }
        deck.load([album("a", songs: ["short"], duration: 2)], cursor: "short")
        deck.play(source: .fullCatalog)
        try await waitUntil { deck.isPlaying }

        factory.last.currentTime = 1.2
        deck.pause()
        XCTAssertEqual(failures, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true
        XCTAssertEqual(try evidence.flushPending().committedSongIDs, ["short"])
    }

    // MARK: - Domain rules

    func testPlaybackSourceMatchesResolvedMusicCapability() {
        XCTAssertEqual(ListeningPlaybackSourceResolver.resolve(capability: .fullPlayback), .fullCatalog)
        XCTAssertEqual(ListeningPlaybackSourceResolver.resolve(capability: .previewOnly), .preview)
        XCTAssertNil(ListeningPlaybackSourceResolver.resolve(capability: .metadataOnly))
        XCTAssertNil(ListeningPlaybackSourceResolver.resolve(capability: .unavailable))
    }

    func testCompletionRequiresStoppedPlaybackAtTrackEnd() {
        XCTAssertFalse(ListeningPlaybackCompletionPolicy.hasEnded(currentTime: 100, duration: 100, isPlaying: true))
        XCTAssertFalse(ListeningPlaybackCompletionPolicy.hasEnded(currentTime: 99, duration: 100, isPlaying: false))
        XCTAssertTrue(ListeningPlaybackCompletionPolicy.hasEnded(currentTime: 99.75, duration: 100, isPlaying: false))
    }

    // MARK: - AVFoundation preview player

    func testPreviewPlayerLeavesOutSongsWithoutAPreview() async throws {
        let service = PreviewListeningPlaybackService(player: AVQueuePlayer())
        defer { service.stop() }
        try await service.load([
            previewItem("p1"),
            ListeningPlaybackItem(songID: "no-preview", duration: 30, previewURL: nil),
            previewItem("p3")
        ], startingAt: "p1", at: 0)

        XCTAssertEqual(service.queuedSongIDs, ["p1", "p3"])
        XCTAssertEqual(service.currentSongID, "p1")
    }

    func testPreviewPlayerRestartsItsLastPreviewAfterTheQueueEnded() async throws {
        let player = AVQueuePlayer()
        let service = PreviewListeningPlaybackService(player: player)
        defer { service.stop() }
        try await service.load([previewItem("p1"), previewItem("p2")], startingAt: "p2", at: 0)

        player.removeAllItems()
        XCTAssertTrue(service.hasEnded)
        XCTAssertEqual(service.currentSongID, "p2")

        try await service.play()
        XCTAssertNotNil(player.currentItem)
        XCTAssertEqual(service.currentSongID, "p2")
        XCTAssertFalse(service.hasEnded)
    }

    func testPreviewResumeKeepsProgressAdvancing() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80_000))
        buffer.frameLength = buffer.frameCapacity
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let player = AVQueuePlayer()
        let deck = ListeningDeck(makeEngine: { _ in PreviewListeningPlaybackService(player: player) })
        defer { deck.eject() }
        let local = ListeningDiscTrack(CatalogSong(
            appleMusicSongID: "local-preview", title: "Local", artistName: "Artist",
            duration: 10, previewURL: url.absoluteString
        ))
        deck.load([ListeningDisc(id: "local", title: "Local", artworkURL: nil, tracks: [local])], cursor: "local-preview")

        deck.play(source: .preview)
        try await waitUntil({ deck.isPlaying }, timeout: .seconds(5))
        try await Task.sleep(for: .seconds(1))
        deck.pause()
        try await waitUntil { !deck.wantsPlayback }
        let pausedAt = deck.time

        deck.play(source: .preview)
        try await waitUntil({ deck.isPlaying }, timeout: .seconds(5))
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(player.timeControlStatus, .playing)
        XCTAssertGreaterThan(deck.time, pausedAt)
    }

    // MARK: - Helpers

    private func album(
        _ id: String,
        songs: [String],
        duration: TimeInterval = 180,
        preview: Bool = false
    ) -> ListeningDisc {
        ListeningDisc(id: id, title: id, artworkURL: nil, tracks: songs.map { track($0, duration: duration, preview: preview) })
    }

    private func compilation(_ showID: UUID, number: Int, songs: [String]) -> ListeningDisc {
        ListeningDisc(
            id: "compilation-\(showID)-\(number)",
            title: "Volume \(number)",
            artworkURL: nil,
            tracks: songs.map { track($0, duration: 180, preview: false) },
            origin: .compilation(showID: showID, number: number)
        )
    }

    private func track(_ id: String, duration: TimeInterval, preview: Bool) -> ListeningDiscTrack {
        ListeningDiscTrack(CatalogSong(
            appleMusicSongID: id, title: id, artistName: "Artist", duration: duration,
            previewURL: preview ? "https://example.com/\(id).m4a" : nil
        ))
    }

    private func previewItem(_ id: String) -> ListeningPlaybackItem {
        ListeningPlaybackItem(songID: id, duration: 30, previewURL: URL(string: "https://example.com/\(id).m4a"))
    }
}

@MainActor
private final class PlayerFactory {
    private(set) var created: [ListeningTestPlayer] = []
    private let configure: (ListeningTestPlayer) -> Void

    init(configure: @escaping (ListeningTestPlayer) -> Void = { _ in }) {
        self.configure = configure
    }

    var last: ListeningTestPlayer { created[created.count - 1] }

    func make(_ source: ListeningPlaybackSource) -> any ListeningPlaybackServicing {
        let player = ListeningTestPlayer(source: source)
        configure(player)
        created.append(player)
        return player
    }
}

private enum DeckTestError: Error {
    case persistence
}
