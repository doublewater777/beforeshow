import XCTest
@testable import BeforeShow

final class ListeningMiniPlayerPlaybackAppearanceTests: XCTestCase {
    func testPreparingUsesPlayingChromeState() {
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .preparing)
        )
    }

    func testPlayingUsesPlayingChromeState() {
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .playing)
        )
    }

    func testPausedAndTerminalStatesDoNotUsePlayingChromeState() {
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .paused)
        )
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .stopped)
        )
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .finished)
        )
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .failed)
        )
    }
}
