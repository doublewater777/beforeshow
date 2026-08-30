import XCTest
@testable import BeforeShow

final class OpeningMemoryWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    func testWindowIsActiveFromStartUntilOneHour() {
        XCTAssertTrue(OpeningMemoryWindow.isActive(now: start, showStart: start, isLive: true))
        XCTAssertTrue(
            OpeningMemoryWindow.isActive(
                now: start.addingTimeInterval(3_599),
                showStart: start,
                isLive: true
            )
        )
        XCTAssertFalse(
            OpeningMemoryWindow.isActive(
                now: start.addingTimeInterval(3_600),
                showStart: start,
                isLive: true
            )
        )
    }

    func testWindowRequiresLivePhase() {
        XCTAssertFalse(
            OpeningMemoryWindow.isActive(
                now: start.addingTimeInterval(600),
                showStart: start,
                isLive: false
            )
        )
        XCTAssertFalse(
            OpeningMemoryWindow.isActive(
                now: start.addingTimeInterval(-60),
                showStart: start,
                isLive: true
            )
        )
    }

    func testNotificationFiresAtShowStartWhenScheduledAhead() {
        XCTAssertEqual(
            OpeningMemoryWindow.notificationFireDate(
                now: start.addingTimeInterval(-86_400),
                showStart: start,
                hasConfirmedEnd: false
            ),
            start
        )
    }

    func testNotificationDoesNotBackfillWhenAddedInsideWindow() {
        let now = start.addingTimeInterval(20 * 60)
        XCTAssertNil(
            OpeningMemoryWindow.notificationFireDate(
                now: now,
                showStart: start,
                hasConfirmedEnd: false
            )
        )
    }

    func testNotificationDoesNotFireAfterWindowOrConfirmedEnd() {
        XCTAssertNil(
            OpeningMemoryWindow.notificationFireDate(
                now: start.addingTimeInterval(3_600),
                showStart: start,
                hasConfirmedEnd: false
            )
        )
        XCTAssertNil(
            OpeningMemoryWindow.notificationFireDate(
                now: start.addingTimeInterval(60),
                showStart: start,
                hasConfirmedEnd: true
            )
        )
    }

    func testLivePrimaryActionIsMemoryCreateOnlyInsideWindow() throws {
        let show = try Show(name: "开场记忆窗", date: start, startTime: start)
        let inside = start.addingTimeInterval(15 * 60)
        let insideState = CurrentShowTimeState(show: show, now: inside)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: insideState, now: inside),
                timeState: insideState,
                now: inside,
                showStart: start,
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            .memoryCreate
        )

        let after = start.addingTimeInterval(90 * 60)
        let afterState = CurrentShowTimeState(show: show, now: after)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: afterState, now: after),
                timeState: afterState,
                now: after,
                showStart: start,
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            .end(live: true)
        )
    }

    func testQuickActionsPromoteEndShowOnlyInsideOpeningWindow() {
        XCTAssertEqual(
            CurrentShowQuickAction.actions(for: .live, inOpeningMemoryWindow: true).first,
            .endShow
        )
        XCTAssertTrue(
            CurrentShowQuickAction.actions(for: .live, inOpeningMemoryWindow: true)
                .contains(.memoryFragments)
        )
        XCTAssertFalse(
            CurrentShowQuickAction.actions(for: .live, inOpeningMemoryWindow: false)
                .contains(.endShow)
        )
    }

    func testMultiDayShowUsesFirstOpeningOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1Start = start
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1Start)!
        let show = try Show(
            name: "三日音乐节",
            date: day1Start,
            startTime: day1Start,
            endDate: calendar.date(byAdding: .day, value: 2, to: day1Start)
        )
        let day2Now = calendar.date(bySettingHour: 14, minute: 10, second: 0, of: day2)!
        let firstStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let day2State = CurrentShowTimeState(show: show, calendar: calendar, now: day2Now)
        let day2Phase = HomeShowPhase(timeState: day2State, now: day2Now)

        XCTAssertEqual(firstStart, day1Start)
        XCTAssertFalse(
            OpeningMemoryWindow.isActive(
                now: day2Now,
                showStart: firstStart,
                isLive: day2Phase == .live
            )
        )
        XCTAssertNotEqual(
            HomeCountdownLockup.primaryAction(
                phase: day2Phase,
                timeState: day2State,
                now: day2Now,
                showStart: firstStart,
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            .memoryCreate
        )
    }
}
