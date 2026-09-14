import XCTest
@testable import BeforeShow

final class ListeningMiniPlayerChromeTests: XCTestCase {
    func testNoTrackKeepsPlainTabsAcrossRootTabs() {
        for tab in BeforeShowTab.allCases {
            XCTAssertEqual(
                ListeningBottomChromeMode.resolve(selectedTab: tab, hasTrack: false),
                .tabsOnly
            )
        }
    }

    func testListenShowsFullPlayerWhenTrackIsLoaded() {
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .listen, hasTrack: true),
            .fullPlayer
        )
    }

    func testOtherTabsMorphListenTabIntoCompactPlayer() {
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .current, hasTrack: true),
            .compactPlayer
        )
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .footprints, hasTrack: true),
            .compactPlayer
        )
    }
}
