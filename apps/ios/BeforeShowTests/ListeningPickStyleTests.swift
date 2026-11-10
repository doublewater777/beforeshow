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
        XCTAssertEqual(ListeningPickStyle.available(supportsShelf3D: false), [.feed, .rack])
        XCTAssertEqual(ListeningPickStyle.available(supportsShelf3D: true), [.shelf3D, .feed, .rack])
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
