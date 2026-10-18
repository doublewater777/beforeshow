import XCTest

@MainActor
final class TimetableSheetFlowTests: XCTestCase {
    private func launchTimetable() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--seed-timetable-live", "-has_completed_feature_onboarding_v1", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
        let open = app.buttons["完整时刻表"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        for _ in 0..<4 where !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 10), "Timetable sheet must open")
        return app
    }

    func testInspectorViewEditCancelAndDone() throws {
        continueAfterFailure = false
        let app = launchTimetable()

        // Tap the lower body of the card; its top row hosts preview / want controls.
        let card = try largestCard(BEGINSWITH: "万能青年旅店", in: app)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()

        let edit = app.buttons["编辑"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists)
        attachScreenshot("inspector-view", app)
        edit.tap()

        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存"].exists)
        attachScreenshot("inspector-edit", app)
        cancel.tap()

        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Cancel returns to view mode")
        app.buttons["完成"].tap()
        XCTAssertTrue(edit.waitForNonExistence(timeout: 5), "Done closes the inspector")
    }

    func testAddPerformanceSavesOnceEvenWhenTappedTwice() throws {
        continueAfterFailure = false
        let app = launchTimetable()

        let more = app.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        app.buttons["添加单场演出"].tap()

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { name.tap() }
        let artist = "UITest \(UUID().uuidString.prefix(6))"
        name.typeText(artist)

        let add = app.buttons["添加"]
        XCTAssertTrue(add.isEnabled)
        attachScreenshot("add-performance", app)
        add.tap()
        if add.exists && add.isHittable { add.tap() }

        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", artist))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        // One card exposes several buttons (card, preview, want); compare with an existing single card.
        let reference = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "NewJeans")).count
        XCTAssertEqual(cards.count, reference, "A double tap must not insert two performances")
    }

    private func attachScreenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func largestCard(BEGINSWITH prefix: String, in app: XCUIApplication) throws -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 20))
        let all = matches.allElementsBoundByIndex.filter(\.isHittable)
        return try XCTUnwrap(all.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }
}
