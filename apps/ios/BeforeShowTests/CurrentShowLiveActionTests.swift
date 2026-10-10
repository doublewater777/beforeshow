import XCTest
@testable import BeforeShow

final class CurrentShowLiveActionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    func testHomeLiveTimetableUsesFestivalTimeZoneBeforeOpening() throws {
        let day = Date(timeIntervalSince1970: 1790956800) // October 3, Taipei midnight.
        let show = try makeTimetableShow(on: day)
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertNil(CurrentShowLiveTimetablePolicy.resolve(for: show, now: day.addingTimeInterval(-1), calendar: deviceCalendar))
        XCTAssertEqual(
            CurrentShowLiveTimetablePolicy.resolve(for: show, now: day.addingTimeInterval(3600), calendar: deviceCalendar)?.phase,
            .upcoming(firstStartsAt: day.addingTimeInterval(20 * 3600))
        )
    }

    func testHomeLiveTimetableDoesNotOverrideEndedCanceledOrUndatedPostponedShow() throws {
        let day = Date(timeIntervalSince1970: 1790956800)
        let now = day.addingTimeInterval(20.5 * 3600)
        XCTAssertEqual(CurrentShowLiveTimetablePolicy.resolve(for: try makeTimetableShow(on: day), now: now)?.phase, .active)
        for status in ["ended", "canceled", "postponed", "historical"] {
            let show = try makeTimetableShow(on: day)
            switch status {
            case "ended": show.markEnded(at: now)
            case "canceled": show.markCanceled()
            case "postponed": show.markPostponed(newDate: nil)
            default: show.wasAddedAsHistorical = true
            }
            XCTAssertNil(CurrentShowLiveTimetablePolicy.resolve(for: show, now: now), status)
        }
    }

    private func makeTimetableShow(on day: Date) throws -> Show {
        let show = try Show(name: "Festival", date: day, startTime: day.addingTimeInterval(20 * 3600), timeZoneIdentifier: "Asia/Taipei")
        let performance = try TimetablePerformance(artistName: "Artist", startsAt: day.addingTimeInterval(20 * 3600), endsAt: day.addingTimeInterval(21 * 3600))
        let stage = try TimetableStage(name: "Main", performances: [performance])
        show.timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [TimetableDay(date: day, stages: [stage])])
        show.timetable?.show = show
        return show
    }

    func testLivePrimaryActionKeepsMemoryCreateAfterFirstHour() throws {
        let end = start.addingTimeInterval(8 * 3_600)
        let show = try Show(name: "整段现场记忆", date: start, startTime: start, endTime: end)
        for seconds in [0, 15 * 60, 3_600, 90 * 60, 7 * 3_600] {
            let now = start.addingTimeInterval(TimeInterval(seconds))
            let state = CurrentShowTimeState(show: show, now: now)
            XCTAssertEqual(
                HomeCountdownLockup.primaryAction(
                    phase: HomeShowPhase(timeState: state, now: now),
                    timeState: state,
                    hasConfirmedEnd: false,
                    hasEndHandler: true
                ),
                .memoryCreate
            )
        }
        let state = CurrentShowTimeState(show: show, now: end)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: state, now: end),
                timeState: state,
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            .end(live: false)
        )
    }

    func testQuickActionsKeepEndShowThroughoutLivePhase() {
        XCTAssertEqual(
            CurrentShowQuickAction.actions(for: .live).first,
            .endShow
        )
        XCTAssertTrue(
            CurrentShowQuickAction.actions(for: .live)
                .contains(.memoryFragments)
        )
        XCTAssertFalse(
            CurrentShowQuickAction.actions(for: .live, canRecordEnd: false)
                .contains(.endShow)
        )
    }

    func testPostShowRetentionQuickActionsLeadWithDispersalCardEntry() {
        let unfinished = CurrentShowQuickAction.actions(
            for: .ended,
            embedsRouteInLocation: true,
            isPostShowRetention: true,
            hasCompletedDispersalCeremony: false
        )
        XCTAssertEqual(unfinished.first, .dispersal(completed: false))
        XCTAssertFalse(unfinished.contains(.timetable))

        let completed = CurrentShowQuickAction.actions(
            for: .ended,
            embedsRouteInLocation: true,
            isPostShowRetention: true,
            hasCompletedDispersalCeremony: true
        )
        XCTAssertEqual(completed.first, .dispersal(completed: true))

        let archived = CurrentShowQuickAction.actions(
            for: .ended,
            embedsRouteInLocation: true,
            isPostShowRetention: false,
            hasCompletedDispersalCeremony: true
        )
        XCTAssertFalse(
            archived.contains { action in
                if case .dispersal = action { return true }
                return false
            }
        )
        XCTAssertTrue(archived.contains(.timetable))
    }

    func testQuickActionsOmitRouteWhenLocationEmbedsIt() {
        XCTAssertFalse(
            CurrentShowQuickAction.actions(for: .pre, embedsRouteInLocation: true)
                .contains(.route)
        )
        XCTAssertTrue(
            CurrentShowQuickAction.actions(for: .pre, embedsRouteInLocation: false)
                .contains(.route)
        )
        XCTAssertEqual(
            CurrentShowQuickAction.actions(
                for: .live,
                embedsRouteInLocation: true
            ).first,
            .endShow
        )
        XCTAssertFalse(
            CurrentShowQuickAction.actions(
                for: .live,
                embedsRouteInLocation: true
            ).contains(.route)
        )
    }

    func testMultiDayShowKeepsMemoryCreateOnLaterDays() throws {
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
        let day2Now = day2.addingTimeInterval(15 * 60)
        let firstStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let day2State = CurrentShowTimeState(show: show, calendar: calendar, now: day2Now)
        let day2Phase = HomeShowPhase(timeState: day2State, now: day2Now)

        XCTAssertEqual(firstStart, day1Start)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: day2Phase,
                timeState: day2State,
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            .memoryCreate
        )
    }
}
