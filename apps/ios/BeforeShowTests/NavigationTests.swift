import XCTest
@testable import BeforeShow

final class NavigationTests: XCTestCase {
    func testTabEnumExposesExactlyTwoMainTabs() {
        let tabs = BeforeShowTab.allCases
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs, [.current, .myShows])
    }

    func testTabRawValuesAndLabelsUseCorrectDomainLanguage() {
        XCTAssertEqual(BeforeShowTab.current.rawValue, "当前")
        XCTAssertEqual(BeforeShowTab.myShows.rawValue, "我的现场")
    }

    /// V4 起设置迁入首页封面右上角的溢出菜单,不再是主 Tab。
    func testSettingsIsNotAMainTab() {
        XCTAssertFalse(BeforeShowTab.allCases.contains { $0.rawValue == "设置" })
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
