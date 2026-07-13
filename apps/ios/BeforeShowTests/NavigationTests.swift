import XCTest
@testable import BeforeShow

final class NavigationTests: XCTestCase {
    func testHomeContentWidthKeepsSymmetricHorizontalInsets() {
        XCTAssertEqual(HomeLayoutMetrics.contentWidth(for: 393, viewportWidth: 393), 357)
        XCTAssertEqual(HomeLayoutMetrics.contentWidth(for: 402, viewportWidth: 402), 366)
        XCTAssertEqual(HomeLayoutMetrics.contentWidth(for: 547, viewportWidth: 402), 366)
    }

    func testTabEnumExposesExactlyThreeMainTabs() {
        let tabs = BeforeShowTab.allCases
        XCTAssertEqual(tabs.count, 3)
        XCTAssertEqual(tabs, [.current, .myShows, .settings])
    }

    func testTabRawValuesAndLabelsUseCorrectDomainLanguage() {
        XCTAssertEqual(BeforeShowTab.current.rawValue, "当前")
        XCTAssertEqual(BeforeShowTab.myShows.rawValue, "我的现场")
        XCTAssertEqual(BeforeShowTab.settings.rawValue, "设置")
    }

    func testTabLabelsDoNotUseForbiddenTerms() {
        let forbiddenTerms = ["行程", "歌单", "余韵", "主演出", "演出列表", "日程"]
        
        for tab in BeforeShowTab.allCases {
            let label = tab.rawValue
            for term in forbiddenTerms {
                XCTAssertFalse(label.contains(term), "Tab label '\(label)' should not contain forbidden term '\(term)'")
            }
        }
    }
}
