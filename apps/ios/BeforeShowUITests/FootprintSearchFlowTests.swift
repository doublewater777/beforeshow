import XCTest

@MainActor
final class FootprintSearchFlowTests: XCTestCase {
    func testSearchResultClosesSearchAndOpensDetailOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--seed-footprint-detail-v41", "-has_completed_feature_onboarding_v1", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        openSearch(in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusAndType("落日", into: field, app: app)

        let result = results(in: app).matching(NSPredicate(format: "label CONTAINS %@", "夏夜回忆现场")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let unrelated = results(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Cheer20")).firstMatch
        XCTAssertTrue(unrelated.waitForNonExistence(timeout: 5), "Query must filter the list")
        waitUntilHittable(result)
        attachScreenshot(named: "search-filtered", app: app)
        result.tap()

        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Search must close after picking a result")
        let detailTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "夏夜回忆现场")).firstMatch
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5), "Detail must open for the picked show")
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        attachScreenshot(named: "detail-opened", app: app)
    }

    func testClearingQueryRestoresAllResults() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--seed-footprint-detail-v41", "-has_completed_feature_onboarding_v1", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        openSearch(in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusAndType("zzzz-no-match", into: field, app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "No matching")).firstMatch.waitForExistence(timeout: 5))

        field.buttons["Clear text"].tap()
        let result = results(in: app).matching(NSPredicate(format: "label CONTAINS %@", "夏夜回忆现场")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
    }

    /// The app restores the last navigation path; pop back to the Footprints root first.
    private func openSearch(in app: XCUIApplication) {
        let tab = app.buttons.matching(identifier: "root.tab.footprints").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let searchEntry = app.buttons["Search Footprints"]
        for _ in 0..<3 where !searchEntry.waitForExistence(timeout: 3) {
            let back = app.navigationBars.buttons["BackButton"]
            if back.exists { back.tap() }
        }
        XCTAssertTrue(searchEntry.waitForExistence(timeout: 5))
        searchEntry.tap()
    }

    private func focusAndType(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        waitUntilHittable(field)
        // iOS 27 simulator: the first tap can land during the sheet settle without taking focus.
        for _ in 0..<3 where !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Keyboard must appear")
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func results(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "footprint.search.result")
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
    }
}
