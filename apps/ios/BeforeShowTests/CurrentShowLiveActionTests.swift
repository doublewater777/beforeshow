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

    func testQuickActionsKeepEndShowThroughoutLivePhase() {
        XCTAssertEqual(
            CurrentShowQuickAction.actions(for: .live).last,
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
        XCTAssertEqual(unfinished, [
            .dispersal(completed: false), .memoryFragments, .companion, .timetable, .ticket
        ])

        let completed = CurrentShowQuickAction.actions(
            for: .ended,
            embedsRouteInLocation: true,
            isPostShowRetention: true,
            hasCompletedDispersalCeremony: true
        )
        XCTAssertEqual(completed, [
            .dispersal(completed: true), .memoryFragments, .companion, .timetable, .ticket
        ])

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

    func testQuickActionsDropRouteOnlyWhenThePrimaryActionIsRoute() {
        let actions: [CurrentShowQuickAction] = [.route, .companion, .timetable, .memoryFragments]
        XCTAssertEqual(CurrentShowQuickAction.deduplicated(actions, primaryAction: .route), [.companion, .timetable, .memoryFragments])
        XCTAssertEqual(CurrentShowQuickAction.deduplicated(actions, primaryAction: .listen), actions)
        XCTAssertEqual(CurrentShowQuickAction.deduplicated(actions, primaryAction: nil), actions)
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
            ).last,
            .endShow
        )
        XCTAssertFalse(
            CurrentShowQuickAction.actions(
                for: .live,
                embedsRouteInLocation: true
            ).contains(.route)
        )
    }

    // MARK: Inline module layout

    func testLoneSquareModuleKeepsItsLifecyclePosition() {
        let rows = CurrentShowInlineLayout.rows(for: [.timetable, .companion, .memoryFragments, .route, .ticket])
        XCTAssertEqual(rows, [.wide(.timetable), .strip(.companion), .wide(.memoryFragments), .wide(.route), .wide(.ticket)])
    }

    func testSquareModulesPairAtTheFirstOnesPosition() {
        let rows = CurrentShowInlineLayout.rows(for: [.dispersal(completed: false), .memoryFragments, .companion, .ticket])
        XCTAssertEqual(rows, [.pair(.dispersal(completed: false), .companion), .wide(.memoryFragments), .wide(.ticket)])
    }

    func testEndedShowDropsRouteFromModules() {
        XCTAssertFalse(CurrentShowQuickAction.actions(for: .ended).contains(.route))
        XCTAssertFalse(CurrentShowQuickAction.actions(for: .ended, isPostShowRetention: true).contains(.route))
    }

    func testMemoryCountReadsTheSameEverywhere() {
        XCTAssertEqual(MemoryMomentTimeline.countText(3), "3 段")
    }
}
