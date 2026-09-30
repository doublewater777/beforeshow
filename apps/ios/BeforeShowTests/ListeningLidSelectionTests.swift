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
        let playback = ListeningFixturePlayer()
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

        playback.elapsed = 97
        playback.start = Date()
        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }

        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(room.timeText, "01:37")
        XCTAssertNil(playback.start)

        room.mechanism.setLid(open: false)
        try await ListenTestData.settle(room) { room.mechanism.isClosed }

        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertNil(playback.start)

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        XCTAssertTrue(room.isPlaying)
        XCTAssertNotNil(playback.start)
        XCTAssertEqual(playback.elapsed, 97, accuracy: 1)
    }
}

