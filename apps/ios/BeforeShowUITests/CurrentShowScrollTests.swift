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
        // iOS 27 native swipe actions label the button "设为当前、设为当前" (icon + title).
        let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "设为当前")).firstMatch
        row.swipeLeft()
        XCTAssertTrue(pin.waitForExistence(timeout: 3), "Horizontal swipes must still reveal the pin action")
        // A tap outside either row dismisses actions without navigating or selecting.
        app.staticTexts["还有"].tap()
        XCTAssertFalse(pin.isHittable)
        XCTAssertFalse(app.navigationBars["现场详情"].exists)
        row.swipeLeft()
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        row.swipeRight()
        XCTAssertFalse(pin.isHittable)

        // A plain tap still opens the show's detail.
        row.tap()
        XCTAssertTrue(app.navigationBars["现场详情"].waitForExistence(timeout: 5))
        app.navigationBars["现场详情"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Setting it current moves it out of the follow-up list.
        row.swipeLeft()
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.tap()
        let followUpRow = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "潮汐 Livehouse · 杭州站", "天后"
        )).firstMatch
        XCTAssertTrue(followUpRow.waitForNonExistence(timeout: 5), "The new current show must leave the follow-up list")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "现场封面，潮汐 Livehouse · 杭州站")).firstMatch.exists)
    }
}
