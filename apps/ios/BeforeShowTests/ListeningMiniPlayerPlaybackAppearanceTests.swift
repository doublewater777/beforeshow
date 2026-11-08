import UIKit
import XCTest
@testable import BeforeShow

final class ListeningMiniPlayerPlaybackAppearanceTests: XCTestCase {
    func testMiniPlayerLeadsBackToItsSurfaceOffListenAndOpensThePlayerOnListen() {
        typealias Bar = ListeningBottomBarPresentation
        XCTAssertEqual(Bar.tap(selectedTab: .current, isVideo: false), .open(.listen))
        XCTAssertEqual(Bar.tap(selectedTab: .footprints, isVideo: true), .open(.watch))
        XCTAssertEqual(Bar.tap(selectedTab: .listen, isVideo: false), .nowPlaying)
        XCTAssertEqual(Bar.tap(selectedTab: .listen, isVideo: true), .video)
    }

    func testBottomBarGeometryLensMatchesActiveTabShapeAndPosition() {
        // Current tab: circle-sized lens, negative offset
        XCTAssertEqual(
            ListeningBottomBarGeometry.lensWidth(for: .current),
            ListeningBottomBarLayout.tabSize - 12
        )
        XCTAssertLessThan(ListeningBottomBarGeometry.selectionOffset(for: .current), 0)

        // Footprints tab: circle-sized lens, positive offset
        XCTAssertEqual(
            ListeningBottomBarGeometry.lensWidth(for: .footprints),
            ListeningBottomBarLayout.tabSize - 12
        )
        XCTAssertGreaterThan(ListeningBottomBarGeometry.selectionOffset(for: .footprints), 0)

        // Listen tab: capsule-sized lens, centered offset
        XCTAssertEqual(
            ListeningBottomBarGeometry.lensWidth(for: .listen),
            ListeningBottomBarLayout.miniPlayerWidth - 12
        )
        XCTAssertEqual(ListeningBottomBarGeometry.selectionOffset(for: .listen), 0)
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
            ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: .failed)
        )
    }

    func testTrackArtworkWinsSoPlaylistsShowEachSong() {
        let trackURL = URL(string: "https://example.com/track.jpg")!
        let discURL = URL(string: "https://example.com/disc.jpg")!

        XCTAssertEqual(
            ListeningMiniPlayerArtworkSource.resolve(
                trackArtworkURL: trackURL,
                discArtworkURL: discURL
            ),
            trackURL
        )
    }

    func testDiscArtworkIsFallbackWhenTrackArtworkIsMissing() {
        let discURL = URL(string: "https://example.com/disc.jpg")!

        XCTAssertEqual(
            ListeningMiniPlayerArtworkSource.resolve(
                trackArtworkURL: nil,
                discArtworkURL: discURL
            ),
            discURL
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

    func testDisplayedArtworkUsesMemoryCacheWhenViewStateIsEmpty() {
        let cached = UIImage()
        let image = ListeningMiniPlayerArtworkImage.displayed(
            loaded: nil,
            url: URL(string: "https://example.com/disc.jpg"),
            memoryImage: { _ in cached }
        )
        XCTAssertIdentical(image, cached)
    }

    func testDisplayedArtworkKeepsLoadedImageWithoutCacheLookup() {
        let loaded = UIImage()
        var lookups = 0
        let image = ListeningMiniPlayerArtworkImage.displayed(
            loaded: loaded,
            url: URL(string: "https://example.com/disc.jpg"),
            memoryImage: { _ in
                lookups += 1
                return UIImage()
            }
        )
        XCTAssertIdentical(image, loaded)
        XCTAssertEqual(lookups, 0)
    }

    func testDisplayedArtworkIsNilWhenNothingIsCached() {
        XCTAssertNil(
            ListeningMiniPlayerArtworkImage.displayed(
                loaded: nil,
                url: URL(string: "https://example.com/disc.jpg"),
                memoryImage: { _ in nil }
            )
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
