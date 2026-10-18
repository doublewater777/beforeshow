import XCTest

@MainActor
final class TextInputFocusTests: XCTestCase {
    /// 摇一摇反馈默认开启时，打开搜索后最多点击一次就必须拿到键盘焦点。
    func testSearchFieldTakesFocusWithShakeFeedbackEnabled() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--seed-footprint-detail-v41", "-has_completed_feature_onboarding_v1", "YES",
            "-feedbackShakeEnabled", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let tab = app.buttons.matching(identifier: "root.tab.footprints").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        app.buttons["Search Footprints"].tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.tap()
        }

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard must appear by the first tap")
        field.typeText("落日")
        XCTAssertEqual(field.value as? String, "落日")
    }
}
