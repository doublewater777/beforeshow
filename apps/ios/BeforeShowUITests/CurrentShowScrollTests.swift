import XCTest

@MainActor final class CurrentShowScrollTests: XCTestCase {
    func testFollowUpRowAllowsVerticalScrollingAndHorizontalReveal() {
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
        row.swipeLeft()
        XCTAssertTrue(app.buttons["设为当前"].waitForExistence(timeout: 3), "Horizontal swipes must still reveal the pin action")
        row.swipeRight()
        XCTAssertFalse(app.buttons["设为当前"].isHittable)
    }
}
