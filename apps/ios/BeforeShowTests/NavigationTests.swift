import XCTest
@testable import BeforeShow

final class NavigationTests: XCTestCase {
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

    func testSingleArtistEmptySheetAutoStartsGenerationWithoutSecondTap() {
        // Concert / livehouse: open empty sheet (browse or generate) → start guessing immediately.
        XCTAssertTrue(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .browse,
                isFestival: false,
                catalogIsEmpty: true,
                didAutoGenerate: false
            )
        )
        XCTAssertTrue(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .generate,
                isFestival: false,
                catalogIsEmpty: true,
                didAutoGenerate: false
            )
        )
        // Already started or already has songs: no auto.
        XCTAssertFalse(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .browse,
                isFestival: false,
                catalogIsEmpty: true,
                didAutoGenerate: true
            )
        )
        XCTAssertFalse(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .browse,
                isFestival: false,
                catalogIsEmpty: false,
                didAutoGenerate: false
            )
        )
        // Explicit edit/share should not burn a generation.
        XCTAssertFalse(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .edit,
                isFestival: false,
                catalogIsEmpty: true,
                didAutoGenerate: false
            )
        )
    }

    func testFestivalEmptySheetOnlyAutoStartsLineupWhenLaunchIsGenerate() {
        XCTAssertTrue(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .generate,
                isFestival: true,
                catalogIsEmpty: true,
                didAutoGenerate: false
            )
        )
        // Browse-only open of empty festival still waits for user (选艺人再猜).
        XCTAssertFalse(
            SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: .browse,
                isFestival: true,
                catalogIsEmpty: true,
                didAutoGenerate: false
            )
        )
    }
}
