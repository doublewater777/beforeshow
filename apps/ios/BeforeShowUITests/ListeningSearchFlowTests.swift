import XCTest

@MainActor
final class ListeningSearchFlowTests: XCTestCase {
    func testResultPushesDetailAndBackKeepsTheQuery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "single-full", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let searchEntry = app.buttons["Search Discs & Songs"]
        XCTAssertTrue(searchEntry.waitForExistence(timeout: 20))
        searchEntry.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Search opens focused")
        field.typeText("最后一班车")

        let result = app.buttons.matching(identifier: "listening.search.result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "The disc detail is pushed inside search, not a new sheet")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "listening-search-detail"
        attachment.lifetime = .keepAlways
        add(attachment)
        back.tap()

        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "最后一班车", "Going back keeps the query and results")
        XCTAssertTrue(result.exists)
    }
}

@MainActor
final class ListeningSearchBrowseTests: XCTestCase {
    func testDefaultPageListsTheCabinetAndConnectsAnArtistInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "unmatched-artist", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let searchEntry = app.buttons["Search Discs & Songs"]
        XCTAssertTrue(searchEntry.waitForExistence(timeout: 20))
        searchEntry.tap()

        let connect = app.buttons.matching(identifier: "listening.search.connectArtist")
        XCTAssertTrue(connect.firstMatch.waitForExistence(timeout: 10), "Unconnected artists are offered without typing")
        let unconnectedBefore = connect.count
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "listening-search-browse"
        attachment.lifetime = .keepAlways
        add(attachment)
        connect.firstMatch.tap()

        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 5), "Connecting is pushed inside search")
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'listening.artistCandidate.'")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        candidate.tap()
        app.buttons["listening.confirmArtist"].tap()

        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Confirming returns to search")
        let browseDisc = app.buttons.matching(identifier: "listening.search.browseDisc").firstMatch
        XCTAssertTrue(browseDisc.waitForExistence(timeout: 15), "The connected artist's discs appear in the list")
        XCTAssertEqual(connect.count, unconnectedBefore - 1)
    }
}
