import UIKit
import XCTest
@testable import BeforeShow

final class ListeningMiniPlayerPlaybackAppearanceTests: XCTestCase {
    func testFixedChromeKeepsSideTabsAndMorphsOnlyCenterSlot() {
        XCTAssertEqual(
            ListeningPolishedBottomChromeMode.resolve(selectedTab: .listen, hasLoadedDisc: true),
            .fullPlayer
        )
        XCTAssertEqual(
            ListeningPolishedBottomChromeMode.resolve(selectedTab: .current, hasLoadedDisc: true),
            .compactPlayer
        )
        XCTAssertEqual(
            ListeningPolishedBottomChromeMode.resolve(selectedTab: .footprints, hasLoadedDisc: true),
            .compactPlayer
        )
        XCTAssertEqual(
            ListeningPolishedBottomChromeMode.resolve(selectedTab: .current, hasLoadedDisc: false),
            .tabsOnly
        )
    }

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
}
