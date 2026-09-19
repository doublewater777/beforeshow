import XCTest
@testable import BeforeShow

final class ListeningPlaybackEvidenceTests: XCTestCase {
    func testFullPlaybackRequiresMoreThanHalfActualListeningTime() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 25, observedAt: 25)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 50, observedAt: 50)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 51, observedAt: 51)), .becameFamiliar(songID: "song-a"))
    }

    func testThresholdRemainsPendingUntilPersistenceCommit() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 51, observedAt: 51)), .becameFamiliar(songID: "song-a"))
        XCTAssertEqual(
            tracker.ingest(full(time: 51, observedAt: 52, isPlaying: false)),
            .becameFamiliar(songID: "song-a")
        )

        tracker.commitFamiliarity(songID: "song-a")

        XCTAssertEqual(tracker.ingest(full(time: 51, observedAt: 53, isPlaying: false)), .none)
    }

    func testForwardSeekDoesNotCountSkippedTime() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 10, observedAt: 10)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 80, observedAt: 11)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 100, observedAt: 31)), .none)
    }

    func testBackwardSeekKeepsPreviouslyAccumulatedListeningTime() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 30, observedAt: 30)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 10, observedAt: 31)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 31, observedAt: 52)), .becameFamiliar(songID: "song-a"))
    }

    func testPausedAndPreviewPlaybackNeverAddEvidence() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 30, observedAt: 30, isPlaying: false)), .none)
        XCTAssertEqual(tracker.ingest(preview(time: 0, observedAt: 31)), .none)
        XCTAssertEqual(tracker.ingest(preview(time: 30, observedAt: 61)), .none)
    }

    func testSongChangeResetsProgressAndFamiliarSongDoesNotEmitAgain() {
        var tracker = ListeningPlaybackEvidenceTracker(alreadyRecordedSongIDs: ["song-b"])

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 30, observedAt: 30)), .none)
        XCTAssertEqual(tracker.ingest(full(songID: "song-b", time: 0, observedAt: 31)), .none)
        XCTAssertEqual(tracker.ingest(full(songID: "song-b", time: 50, observedAt: 81)), .none)
    }

    func testExplicitSeekBreaksContinuityEvenWhenJumpLooksLikePlayback() {
        var tracker = ListeningPlaybackEvidenceTracker()

        XCTAssertEqual(tracker.ingest(full(time: 0, observedAt: 0)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 20, observedAt: 20)), .none)
        tracker.breakContinuity()
        XCTAssertEqual(tracker.ingest(full(time: 21, observedAt: 21)), .none)
        XCTAssertEqual(tracker.ingest(full(time: 50, observedAt: 50)), .none)
    }

    private func full(
        songID: String = "song-a",
        time: TimeInterval,
        observedAt: TimeInterval,
        isPlaying: Bool = true
    ) -> ListeningPlaybackSample {
        ListeningPlaybackSample(
            songID: songID,
            source: .fullCatalog,
            currentTime: time,
            duration: 100,
            isPlaying: isPlaying,
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }

    private func preview(time: TimeInterval, observedAt: TimeInterval) -> ListeningPlaybackSample {
        ListeningPlaybackSample(
            songID: "song-a",
            source: .preview,
            currentTime: time,
            duration: 30,
            isPlaying: true,
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }
}
