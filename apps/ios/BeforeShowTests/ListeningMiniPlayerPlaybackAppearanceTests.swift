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

    func testLoadedDiscArtworkWinsOverTrackArtwork() {
        let trackURL = URL(string: "https://example.com/track.jpg")!
        let discURL = URL(string: "https://example.com/disc.jpg")!

        XCTAssertEqual(
            ListeningMiniPlayerArtworkSource.resolve(
                trackArtworkURL: trackURL,
                discArtworkURL: discURL
            ),
            discURL
        )
    }

    func testTrackArtworkIsFallbackWhenDiscArtworkIsMissing() {
        let trackURL = URL(string: "https://example.com/track.jpg")!

        XCTAssertEqual(
            ListeningMiniPlayerArtworkSource.resolve(
                trackArtworkURL: trackURL,
                discArtworkURL: nil
            ),
            trackURL
        )
    }

    func testArtworkResolverReturnsNilWhenNoArtworkExists() {
        XCTAssertNil(
            ListeningMiniPlayerArtworkSource.resolve(
                trackArtworkURL: nil,
                discArtworkURL: nil
            )
        )
    }
}
