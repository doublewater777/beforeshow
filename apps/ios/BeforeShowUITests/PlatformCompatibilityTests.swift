import XCTest

@MainActor
final class PlatformCompatibilityTests: XCTestCase {
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
