import XCTest

@MainActor final class CurrentShowScrollTests: XCTestCase {
    func testFollowUpRowScrollsAndSetsCurrentFromDetail() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--seed-app-store-screenshots", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "潮汐 Livehouse")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 {
            if row.isHittable && row.frame.midY < app.windows.firstMatch.frame.height - 130 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        let before = row.frame.midY
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)))
        XCTAssertGreaterThan(row.frame.midY, before + 40, "Dragging down from a follow-up row must scroll the page")

        for _ in 0..<5 {
            if row.isHittable && row.frame.midY < app.windows.firstMatch.frame.height - 130 { break }
            scroll.swipeUp()
        }
        // Rows only open details; setting current lives on the detail page.
        row.tap()
        let detail = app.navigationBars["现场详情"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let setCurrent = app.buttons["设为当前现场"]
        XCTAssertTrue(setCurrent.waitForExistence(timeout: 3))
        setCurrent.tap()
        XCTAssertTrue(setCurrent.waitForNonExistence(timeout: 5))
        detail.buttons.firstMatch.tap()

        let followUpRow = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "潮汐 Livehouse · 杭州站", "天后"
        )).firstMatch
        XCTAssertTrue(followUpRow.waitForNonExistence(timeout: 5), "The new current show must leave the follow-up list")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "现场封面，潮汐 Livehouse · 杭州站")).firstMatch.exists)
    }
}
