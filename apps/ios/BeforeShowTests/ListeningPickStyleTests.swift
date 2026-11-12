import XCTest
@testable import BeforeShow

final class ListeningPickStyleTests: XCTestCase {
    func testNewUserStartsOnTheShelfWhileTrialLasts() {
        XCTAssertEqual(resolve("", trialUsed: 0), .shelf3D)
        XCTAssertEqual(resolve("", trialUsed: 2), .shelf3D)
    }

    func testFreeUserFallsBackToFeedWhenTrialRunsOut() {
        XCTAssertEqual(resolve("shelf3D", trialUsed: 3), .feed)
        XCTAssertEqual(resolve("", trialUsed: 3), .feed)
    }

    func testAnOpenAlreadyCountedKeepsTheShelf() {
        XCTAssertEqual(resolve("shelf3D", trialUsed: 3, counted: true), .shelf3D)
    }

    func testCarouselIsProAndSharesTheTrial() {
        XCTAssertEqual(resolve("ring", trialUsed: 2), .ring)
        XCTAssertEqual(resolve("ring", trialUsed: 3), .feed)
        XCTAssertEqual(resolve("ring", trialUsed: 3, counted: true), .ring)
        XCTAssertEqual(resolve("ring", isPro: true, trialUsed: 99), .ring)
        XCTAssertEqual(resolve("ring", trialUsed: 0, supports: false), .ring)
    }

    func testTossAndFeatherAreProAndShareTheTrial() {
        for style in [ListeningPickStyle.toss, .feather] {
            XCTAssertTrue(style.isPro)
            XCTAssertEqual(resolve(style.rawValue, trialUsed: 2), style)
            XCTAssertEqual(resolve(style.rawValue, trialUsed: 3), .feed)
            XCTAssertEqual(resolve(style.rawValue, trialUsed: 3, counted: true), style)
            XCTAssertEqual(resolve(style.rawValue, isPro: true, trialUsed: 99), style)
        }
    }

    func testProAlwaysGetsTheShelf() {
        XCTAssertEqual(resolve("shelf3D", isPro: true, trialUsed: 99), .shelf3D)
    }

    func testFreeStylesStayAsChosen() {
        XCTAssertEqual(resolve("feed", trialUsed: 0), .feed)
        XCTAssertEqual(resolve("rack", trialUsed: 99), .rack)
    }

    func testRetiredOrUnknownValueStartsOnTheShelf() {
        XCTAssertEqual(resolve("diagonal", trialUsed: 0), .shelf3D)
    }

    func testWithoutShelfSupportFeedIsShownAndShelfIsNotOffered() {
        XCTAssertEqual(resolve("", isPro: true, trialUsed: 0, supports: false), .feed)
        XCTAssertEqual(ListeningPickStyle.available(supportsShelf3D: false), [.feed, .rack, .ring, .toss, .feather])
        XCTAssertEqual(ListeningPickStyle.available(supportsShelf3D: true), [.shelf3D, .feed, .rack, .ring, .toss, .feather])
    }

    func testTrialOpensLeft() {
        XCTAssertNil(ListeningPickStyle.trialOpensLeft(isPro: true, used: 0))
        XCTAssertEqual(ListeningPickStyle.trialOpensLeft(isPro: false, used: 1), 2)
        XCTAssertEqual(ListeningPickStyle.trialOpensLeft(isPro: false, used: 5), 0)
    }

    private func resolve(
        _ stored: String, isPro: Bool = false, trialUsed: Int, counted: Bool = false, supports: Bool = true
    ) -> ListeningPickStyle {
        ListeningPickStyle.resolved(
            storedRawValue: stored, isPro: isPro, trialOpensUsed: trialUsed,
            countedThisOpen: counted, supportsShelf3D: supports
        )
    }
}
