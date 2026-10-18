import XCTest

@MainActor
final class PlatformCompatibilityTests: XCTestCase {
    func testSettingsDestinationsRemainResponsive() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = [
            "--open-settings", "-has_completed_feature_onboarding_v1", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let widgets = app.buttons["Widgets"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 20))
        widgets.tap()

        let picker = app.segmentedControls.firstMatch
        let lockScreen = picker.buttons["Lock Screen"]
        XCTAssertTrue(lockScreen.waitForExistence(timeout: 10))
        lockScreen.press(forDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: lockScreen
        )], timeout: 5), .completed)
        let homeScreen = picker.buttons["Home Screen"]
        homeScreen.press(forDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: homeScreen
        )], timeout: 5), .completed)

        app.navigationBars["Widgets"].buttons.firstMatch.tap()
        XCTAssertTrue(widgets.waitForExistence(timeout: 5))
        XCTAssertTrue(widgets.isHittable)

        for title in ["Privacy & Local Data", "Feedback", "About BeforeShow"] {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<5 {
                if link.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(link.isHittable, title)
            link.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 10), title)
            navigationBar.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        }

        app.navigationBars["Settings"].buttons.firstMatch.tap()
        _ = try visibleTab("root.tab.current", in: app)
    }

    func testRootTabsRemainUsableAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Reuse the in-memory listening fixture; do not seed the device's show library.
        app.launchArguments = ["--listen-fixture", "no-current", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        for id in ["root.tab.current", "root.tab.footprints", "root.tab.listen"] {
            try visibleTab(id, in: app).tap()
            XCTAssertTrue(try visibleTab(id, in: app).isSelected)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = id
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        app.terminate()
        app.launch()
        XCTAssertTrue(try visibleTab("root.tab.listen", in: app).isSelected)
    }

    private func visibleTab(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        let query = app.buttons.matching(identifier: id)
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in query.allElementsBoundByIndex.contains { $0.isHittable } },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 20), .completed, id)
        return try XCTUnwrap(query.allElementsBoundByIndex.first { $0.isHittable }, id)
    }
}
