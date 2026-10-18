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

    @MainActor
    func testContinuousRotationStorePreservesAngleAcrossInstancesWhenPaused() {
        let store = CDContinuousRotationStore.shared
        let trackID = "test-track-\(UUID().uuidString)"
        defer { store.reset(identity: trackID) }

        // Simulate spinning for 2.25 seconds at 60/9 rpm (1 rev = 9 seconds).
        // 2.25 / 9 = 0.25 rev = pi / 2 radians (90 degrees).
        let t0: CFTimeInterval = 100.0
        let rpm = 60.0 / 9.0
        store.update(identity: trackID, isRotating: true, revolutionsPerMinute: rpm, at: t0)

        let t1 = t0 + 2.25
        let pausedAngle = store.update(identity: trackID, isRotating: false, revolutionsPerMinute: rpm, at: t1)
        XCTAssertEqual(pausedAngle, .pi / 2, accuracy: 0.001)

        // Switching from Current tab to Footprints tab 10 seconds later while paused:
        // Instance 2 (Footprints) queries the angle at t2.
        let t2 = t1 + 10.0
        let footprintsAngle = store.currentAngle(for: trackID, at: t2)
        XCTAssertEqual(footprintsAngle, pausedAngle, accuracy: 0.000001)

        // Updating with isRotating: false on the new tab retains the exact angle.
        let confirmedAngle = store.update(identity: trackID, isRotating: false, revolutionsPerMinute: rpm, at: t2)
        XCTAssertEqual(confirmedAngle, pausedAngle, accuracy: 0.000001)
    }

    @MainActor
    func testContinuousRotationStorePreservesContinuousPhaseAcrossTabSwitchWhenSpinning() {
        let store = CDContinuousRotationStore.shared
        let trackID = "test-track-spinning-\(UUID().uuidString)"
        defer { store.reset(identity: trackID) }

        let t0: CFTimeInterval = 200.0
        let rpm = 60.0 / 9.0
        store.update(identity: trackID, isRotating: true, revolutionsPerMinute: rpm, at: t0)

        // At t1 (3 seconds later = 120 degrees = 2*pi/3 rad), user switches to Footprints tab.
        let t1 = t0 + 3.0
        let transitionAngle = store.currentAngle(for: trackID, at: t1)
        XCTAssertEqual(transitionAngle, (2.0 * .pi) / 3.0, accuracy: 0.001)

        // Footprints tab mounts and calls update while still spinning:
        let footprintsMountAngle = store.update(identity: trackID, isRotating: true, revolutionsPerMinute: rpm, at: t1)
        XCTAssertEqual(footprintsMountAngle, transitionAngle, accuracy: 0.001)

        // 1.5 seconds later (t2), verify continuous rotation has progressed without resetting:
        let t2 = t1 + 1.5
        let progressedAngle = store.currentAngle(for: trackID, at: t2)
        // Total elapsed: 4.5 seconds = 0.5 rev = pi rad (180 degrees).
        XCTAssertEqual(progressedAngle, .pi, accuracy: 0.001)
    }
}
