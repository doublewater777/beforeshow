import XCTest
@testable import BeforeShow

final class ListeningPlaybackStateMachineTests: XCTestCase {
    func testPlaybackSourceMatchesResolvedMusicCapability() {
        XCTAssertEqual(ListeningPlaybackSourceResolver.resolve(capability: .fullPlayback), .fullCatalog)
        XCTAssertEqual(ListeningPlaybackSourceResolver.resolve(capability: .previewOnly), .preview)
        XCTAssertNil(ListeningPlaybackSourceResolver.resolve(capability: .metadataOnly))
        XCTAssertNil(ListeningPlaybackSourceResolver.resolve(capability: .unavailable))
    }

    func testCompletionRequiresStoppedPlaybackAtTrackEnd() {
        XCTAssertFalse(ListeningPlaybackCompletionPolicy.hasEnded(
            currentTime: 100,
            duration: 100,
            isPlaying: true
        ))
        XCTAssertFalse(ListeningPlaybackCompletionPolicy.hasEnded(
            currentTime: 99,
            duration: 100,
            isPlaying: false
        ))
        XCTAssertTrue(ListeningPlaybackCompletionPolicy.hasEnded(
            currentTime: 99.75,
            duration: 100,
            isPlaying: false
        ))
    }

    func testPreparePlayPauseAndFinishTransitions() {
        var machine = ListeningPlaybackStateMachine()

        XCTAssertEqual(machine.handle(.prepareStarted(source: .fullCatalog)), .preparing(source: .fullCatalog))
        XCTAssertEqual(
            machine.handle(.sample(sample(time: 0, isPlaying: false))),
            .ready(songID: "song-a", source: .fullCatalog, currentTime: 0, duration: 100)
        )
        XCTAssertEqual(
            machine.handle(.sample(sample(time: 10, isPlaying: true))),
            .playing(songID: "song-a", source: .fullCatalog, currentTime: 10, duration: 100)
        )
        XCTAssertEqual(
            machine.handle(.sample(sample(time: 10, isPlaying: false))),
            .paused(songID: "song-a", source: .fullCatalog, currentTime: 10, duration: 100)
        )
        XCTAssertEqual(
            machine.handle(.sample(sample(time: 10, isPlaying: false))),
            .paused(songID: "song-a", source: .fullCatalog, currentTime: 10, duration: 100)
        )
        XCTAssertEqual(
            machine.handle(.finished(songID: "song-a")),
            .finished(songID: "song-a", source: .fullCatalog, duration: 100)
        )
    }

    func testNewSongSampleReplacesFinishedState() {
        var machine = ListeningPlaybackStateMachine()
        _ = machine.handle(.prepareStarted(source: .preview))
        _ = machine.handle(.sample(sample(songID: "song-a", source: .preview, time: 30, duration: 30, isPlaying: false)))
        _ = machine.handle(.finished(songID: "song-a"))

        XCTAssertEqual(
            machine.handle(.sample(sample(songID: "song-b", source: .preview, time: 0, duration: 30, isPlaying: true))),
            .playing(songID: "song-b", source: .preview, currentTime: 0, duration: 30)
        )
    }

    func testFailureAndResetAreExplicitStates() {
        var machine = ListeningPlaybackStateMachine()

        XCTAssertEqual(machine.handle(.failed), .failed)
        XCTAssertEqual(machine.handle(.reset), .idle)
    }

    private func sample(
        songID: String = "song-a",
        source: ListeningPlaybackSource = .fullCatalog,
        time: TimeInterval,
        duration: TimeInterval = 100,
        isPlaying: Bool
    ) -> ListeningPlaybackSample {
        ListeningPlaybackSample(
            songID: songID,
            source: source,
            currentTime: time,
            duration: duration,
            isPlaying: isPlaying,
            observedAt: Date(timeIntervalSince1970: time)
        )
    }
}
