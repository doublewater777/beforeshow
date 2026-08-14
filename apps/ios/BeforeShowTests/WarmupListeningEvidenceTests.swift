import XCTest
@testable import BeforeShow

final class WarmupListeningEvidenceTests: XCTestCase {
    func testContinuousFullPlaybackMarksHeardAtHalfKnownDuration() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: true)), .heard(songID: "song-a"))
    }

    func testForwardSeekDoesNotCountSkippedTime() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 10, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 80, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 100, duration: 100, isPlaying: true)), .none)
    }

    func testBackwardSeekDoesNotSubtractOrCountSkippedRange() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 30, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 10, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 30, duration: 100, isPlaying: true)), .heard(songID: "song-a"))
    }

    func testPauseTimeDoesNotCountAndResumeContinuesFromCurrentPosition() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: false)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: false)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 75, duration: 100, isPlaying: true)), .heard(songID: "song-a"))
    }

    func testPreviewPlaybackNeverMarksHeard() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(preview(songID: "song-a", currentTime: 0, duration: 30, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(preview(songID: "song-a", currentTime: 15, duration: 30, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(preview(songID: "song-a", currentTime: 30, duration: 30, isPlaying: true)), .none)
    }

    func testHeardEventIsEmittedOnlyOnceForRepeatedPlayback() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: true)), .heard(songID: "song-a"))
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: true)), .none)
    }

    func testChangingSongsResetsPlaybackCounter() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-b", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-b", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-b", currentTime: 50, duration: 100, isPlaying: true)), .heard(songID: "song-b"))
    }

    func testManualMarkUsesSeparateResultAndPreventsLaterAutoEmission() {
        var evidence = WarmupListeningEvidence()

        XCTAssertEqual(evidence.markHeardManually(songID: "song-a"), .manuallyMarked(songID: "song-a"))
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 0, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 25, duration: 100, isPlaying: true)), .none)
        XCTAssertEqual(evidence.update(full(songID: "song-a", currentTime: 50, duration: 100, isPlaying: true)), .none)
    }

    private func full(
        songID: String,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool
    ) -> WarmupListeningEvidence.PlaybackSample {
        WarmupListeningEvidence.PlaybackSample(
            songID: songID,
            source: .appleMusicFullPlayback,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func preview(
        songID: String,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool
    ) -> WarmupListeningEvidence.PlaybackSample {
        WarmupListeningEvidence.PlaybackSample(
            songID: songID,
            source: .appleMusicPreview,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
}
