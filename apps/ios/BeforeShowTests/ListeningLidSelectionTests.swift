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
        XCTAssertEqual(room.trackIndex, 0, "opening the lid may stop/reset the transport")

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
}
