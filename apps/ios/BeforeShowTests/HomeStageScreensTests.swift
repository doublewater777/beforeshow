import XCTest
@testable import BeforeShow

final class HomeStageScreensTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testSingleActOnStageShowsNextOnRightScreen() throws {
        let lead = perf("King Gizzard", start: -1800, end: 2100)
        let next = perf("万能青年旅店", start: 2700, end: 6300)
        let screens = try XCTUnwrap(HomeStageScreens.resolve(state(.active, current: [lead], upcoming: [next])))

        XCTAssertEqual(screens.main, .live(lead))
        XCTAssertNil(screens.left)
        XCTAssertEqual(screens.right, .next(next))
    }

    func testParallelActsTakeTheSideScreens() throws {
        let lead = perf("King Gizzard", start: -1800, end: 2100)
        let second = perf("落日飞车", start: -600, end: 3000)
        let third = perf("Wednesday", start: -300, end: 3300)
        let next = perf("NewJeans", start: 2700, end: 6300)

        let two = try XCTUnwrap(HomeStageScreens.resolve(state(.active, current: [lead, second], upcoming: [next])))
        XCTAssertEqual(two.left, .live(second))
        XCTAssertEqual(two.right, .next(next))

        let three = try XCTUnwrap(HomeStageScreens.resolve(state(.active, current: [lead, second, third], upcoming: [next])))
        XCTAssertEqual(three.left, .live(second))
        XCTAssertEqual(three.right, .live(third))
    }

    func testChangeoverPutsNextActOnMainScreen() throws {
        let later = perf("草东没有派对", start: 5400, end: 9000)
        let next = perf("万能青年旅店", start: 720, end: 4320)
        let screens = try XCTUnwrap(HomeStageScreens.resolve(state(.active, current: [], upcoming: [later, next])))

        XCTAssertEqual(screens.main, .next(next))
        XCTAssertEqual(screens.right, .next(later))
    }

    func testPosterReturnsWhenTheDayIsDone() {
        XCTAssertNil(HomeStageScreens.resolve(state(.dayEnded(nextDayStartsAt: nil), current: [], upcoming: [])))
        XCTAssertNil(HomeStageScreens.resolve(state(.fullyEnded, current: [], upcoming: [])))
    }

    private func state(_ phase: LiveModePhase, current: [LivePerformanceSnapshot], upcoming: [LivePerformanceSnapshot]) -> LiveModeState {
        LiveModeState(phase: phase, activeDayID: nil, currentPerformances: current, upcomingPerformances: upcoming, hasAnyInterested: false)
    }

    private func perf(_ name: String, start: TimeInterval, end: TimeInterval) -> LivePerformanceSnapshot {
        LivePerformanceSnapshot(
            id: UUID(),
            artistName: name,
            stageID: UUID(),
            stageName: "草莓舞台",
            startsAt: now.addingTimeInterval(start),
            endsAt: now.addingTimeInterval(end),
            isInterested: false,
            secondsUntilStart: max(0, start),
            secondsUntilEnd: max(0, end)
        )
    }
}
