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
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "Search opens on the list, not the keyboard")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
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
final class ListeningDiscPickFlowTests: XCTestCase {
    func testNativeFilterKeepsBothSwipeDirectionsWithinSelectedType() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "artist-library", "--listen-open-pick",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let filter = app.buttons["listening.pickDisc.filter"]
        let card = app.otherElements["listening.pickDisc.card"]
        let title = card.staticTexts["listening.discDetail.title"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        filter.tap()
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "listening-disc-pick-native-filter"
        menu.lifetime = .keepAlways
        add(menu)
        app.buttons["Albums"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Album"))
        app.buttons["listening.pickDisc.redraw"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: filter)
        waitForExpectations(timeout: 5)

        filter.tap()
        app.buttons["Singles & EPs"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Single") || title.label.contains("EP"))
        for direction: CGFloat in [-1, 1, 1, -1] {
            let previous = title.label
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: direction * 200, dy: 0)),
                        withVelocity: 600, thenHoldForDuration: 0)
            expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: title)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(title.label.contains("Single") || title.label.contains("EP"), "Old album history must be cleared")
        }
    }

    func testEmptyFilterCanBeChangedWithoutClosingThePicker() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "single-full", "--listen-open-pick",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let filter = app.buttons["listening.pickDisc.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        filter.tap()
        app.buttons["Singles & EPs"].tap()
        XCTAssertTrue(app.staticTexts["listening.pickDisc.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["listening.pickDisc.confirm"].exists)
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["listening.pickDisc.confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["listening.pickDisc.empty"].exists)
    }

    func testRedrawKeepsActionsVisibleAndChangesTheDiscInPlace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "artist-library", "--listen-open-pick",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let confirm = app.buttons["listening.pickDisc.confirm"]
        let redraw = app.buttons["listening.pickDisc.redraw"]
        let card = app.otherElements["listening.pickDisc.card"]
        let title = card.staticTexts["listening.discDetail.title"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(redraw.isHittable)
        let firstTitle = title.label
        let initialCardHeight = card.frame.height

        redraw.tap()
        let changedTitle = NSPredicate(format: "label != %@", firstTitle)
        expectation(for: changedTitle, evaluatedWith: title)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(redraw.isHittable)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let beforeShortDrag = title.label
        let center = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 25, dy: 0)),
                     withVelocity: 50, thenHoldForDuration: 0.3)
        XCTAssertEqual(title.label, beforeShortDrag, "A short drag returns the same card")

        XCTAssertEqual(card.frame.height, initialCardHeight, accuracy: 1, "Card height stays fixed across discs")
        let secondTitle = title.label
        for (direction, expectedTitle): (CGFloat, String) in [(-1, firstTitle), (1, secondTitle)] {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: direction * 200, dy: 15)),
                        withVelocity: 600, thenHoldForDuration: 0)
            expectation(for: NSPredicate(format: "label == %@", expectedTitle), evaluatedWith: title)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(confirm.isHittable)
            XCTAssertTrue(redraw.isHittable)
            XCTAssertEqual(card.frame.height, initialCardHeight, accuracy: 1)
        }

        for _ in 0..<2 {
            let previousTitle = title.label
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)),
                        withVelocity: 600, thenHoldForDuration: 0)
            expectation(for: NSPredicate(format: "label != %@", previousTitle), evaluatedWith: title)
            waitForExpectations(timeout: 5)
        }
        for expectedTitle in [firstTitle, secondTitle] {
            redraw.tap()
            expectation(for: NSPredicate(format: "label == %@", expectedTitle), evaluatedWith: title)
            waitForExpectations(timeout: 5)
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "listening-disc-pick-swipe-deck"
        attachment.lifetime = .keepAlways
        add(attachment)
        confirm.tap()
        XCTAssertTrue(redraw.waitForNonExistence(timeout: 5), "Loading closes the picker")
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
