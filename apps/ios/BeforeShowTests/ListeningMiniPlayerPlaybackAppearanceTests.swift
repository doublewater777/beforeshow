import UIKit
import XCTest
@testable import BeforeShow

final class ListeningMiniPlayerPlaybackAppearanceTests: XCTestCase {
    func testMiniPlayerReplacesListenControlOnlyOffListenWithLoadedDisc() {
        XCTAssertFalse(
            ListeningBottomBarPresentation.showsMiniPlayer(
                selectedTab: .current,
                hasLoadedDisc: false
            )
        )
        XCTAssertTrue(
            ListeningBottomBarPresentation.showsMiniPlayer(
                selectedTab: .current,
                hasLoadedDisc: true
            )
        )
        XCTAssertFalse(
            ListeningBottomBarPresentation.showsMiniPlayer(
                selectedTab: .listen,
                hasLoadedDisc: true
            )
        )
        XCTAssertTrue(
            ListeningBottomBarPresentation.showsMiniPlayer(
                selectedTab: .footprints,
                hasLoadedDisc: true
            )
        )
    }

    func testPreparingUsesPlayingChromeState() {
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .preparing)
        )
    }

    func testWaitingPlayingAndSeekingUsePlayingChromeState() {
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .waiting)
        )
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .playing)
        )
        XCTAssertTrue(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .seeking)
        )
    }

    func testPausedAndTerminalStatesDoNotUsePlayingChromeState() {
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .paused)
        )
        XCTAssertFalse(
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .interrupted)
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

    func testMiniPlayerSwipeLeftAdvancesToNextTrack() {
        XCTAssertEqual(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: -60, height: 8)
            ),
            .next
        )
    }

    func testMiniPlayerSwipeRightReturnsToPreviousTrack() {
        XCTAssertEqual(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: 60, height: -8)
            ),
            .previous
        )
    }

    func testMiniPlayerSwipeIgnoresShortAndVerticalDrags() {
        XCTAssertNil(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: 30, height: 2)
            )
        )
        XCTAssertNil(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: 60, height: 55)
            )
        )
    }

    func testMiniPlayerFastFlickCommitsBeforeDistanceThreshold() {
        XCTAssertEqual(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: -32, height: 3),
                predictedEndTranslation: CGSize(width: -104, height: 4)
            ),
            .next
        )
    }

    func testMiniPlayerSlowShortDragStillSettlesBack() {
        XCTAssertNil(
            ListeningMiniPlayerSwipeIntent.action(
                for: CGSize(width: 40, height: 3),
                predictedEndTranslation: CGSize(width: 58, height: 4)
            )
        )
    }

    func testMiniPlayerUnavailableEdgeUsesRubberBandResistance() {
        let translation = CGSize(width: 80, height: 2)
        XCTAssertEqual(
            ListeningMiniPlayerSwipeIntent.trackedOffset(
                for: translation,
                canNavigate: true
            ),
            80,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            ListeningMiniPlayerSwipeIntent.trackedOffset(
                for: translation,
                canNavigate: false
            ),
            14.4,
            accuracy: 0.000001
        )
    }
}
