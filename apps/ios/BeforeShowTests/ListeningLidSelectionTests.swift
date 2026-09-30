import XCTest
@testable import BeforeShow

@MainActor
final class ListeningLidSelectionTests: XCTestCase {
    func testClosingLidRestoresSelectedTrackWhenDiscWasNotRemoved() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)

        let disc = try XCTUnwrap(room.browseArtists.first?.albums.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        XCTAssertNotEqual(songID, disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)
        XCTAssertEqual(room.track?.id, songID)

        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(room.trackIndex, disc.tracks.count - 1)

        room.mechanism.setLid(open: false)
        try await ListenTestData.settle(room) { room.mechanism.isClosed }

        XCTAssertEqual(room.track?.id, songID)
        XCTAssertFalse(room.isPlaying)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertFalse(reopened.isPlaying)

        room.mechanism.motion.stop()
        reopened.mechanism.motion.stop()
    }

    func testClosingSameDiscKeepsResumePointWithoutAutoplay() async throws {
        let (container, show) = try ListenTestData.make()
        let playback = LidResumePlaybackService()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.setCurrentTime(97)
        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }

        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(room.timeText, "01:37")
        XCTAssertEqual(playback.stopCount, 1)

        room.mechanism.setLid(open: false)
        try await ListenTestData.settle(room) { room.mechanism.isClosed }

        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(playback.prepareCount, 1)
        XCTAssertEqual(playback.playCount, 1)

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        XCTAssertEqual(playback.prepareCount, 2)
        XCTAssertEqual(playback.playCount, 2)
        XCTAssertEqual(playback.seekTimes.last, 97)
        XCTAssertEqual(playback.currentTime, 97)
    }
}

@MainActor
private final class LidResumePlaybackService: ListeningPlaybackServicing {
    private var items: [ListeningPlaybackItem] = []
    private var index = 0
    private var source: ListeningPlaybackSource = .fullCatalog
    private(set) var currentTime: TimeInterval = 0
    private var playing = false
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var seekTimes: [TimeInterval] = []

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        guard !items.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        self.items = items
        self.source = source
        index = startingAtSongID.flatMap { songID in
            items.firstIndex { $0.songID == songID }
        } ?? 0
        currentTime = 0
        playing = false
        prepareCount += 1
    }

    func play() async throws {
        playing = true
        playCount += 1
    }

    func pause() {
        playing = false
    }

    func skipToNext() async throws {
        guard index + 1 < items.count else { throw ListeningPlaybackError.queueBoundary }
        index += 1
        currentTime = 0
    }

    func skipToPrevious() async throws {
        guard index > 0 else { throw ListeningPlaybackError.queueBoundary }
        index -= 1
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        seekTimes.append(time)
    }

    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        return ListeningPlaybackSample(
            songID: item.songID,
            source: source,
            currentTime: currentTime,
            duration: item.duration,
            isPlaying: playing,
            observedAt: observedAt
        )
    }

    func stop() {
        playing = false
        items = []
        index = 0
        currentTime = 0
        stopCount += 1
    }

    func setCurrentTime(_ time: TimeInterval) {
        currentTime = time
    }
}
