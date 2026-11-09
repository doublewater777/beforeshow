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
            .dispersal(completed: false), .memoryFragments, .ticket, .companion, .timetable
        ])

        let completed = CurrentShowQuickAction.actions(
            for: .ended,
            embedsRouteInLocation: true,
            isPostShowRetention: true,
            hasCompletedDispersalCeremony: true
        )
        XCTAssertEqual(completed, [
            .dispersal(completed: true), .memoryFragments, .ticket, .companion, .timetable
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

    // MARK: Module order

    func testPreShowLeadsWithCompanionAndSetlistAndLeavesTheTicketStubLast() {
        let modules = CurrentShowModuleOrder.modules(actions: CurrentShowQuickAction.actions(for: .pre), phase: .pre, timetableIsLive: false)
        XCTAssertEqual(modules, [
            .action(.companion), .record(.setlist), .action(.timetable), .record(.merch), .record(.spending),
            .action(.route), .action(.memoryFragments), .action(.ticket)
        ])
    }

    func testTheRouteMapIsNeverTheFirstModule() {
        for phase in [HomeShowPhase.pre, .live] {
            let all = CurrentShowQuickAction.actions(for: phase)
            // 其他模块都被拿掉也不能让路线顶到第一。
            for actions in [all, [.route, .ticket], [.route, .memoryFragments]] {
                let modules = CurrentShowModuleOrder.modules(actions: actions, phase: phase, timetableIsLive: false)
                XCTAssertNotEqual(modules.first, .action(.route), "\(phase) \(actions)")
            }
        }
    }

    func testLiveTimetableComesFirstDuringTheShow() {
        let modules = CurrentShowModuleOrder.modules(actions: CurrentShowQuickAction.actions(for: .live), phase: .live, timetableIsLive: true)
        XCTAssertEqual(modules, [
            .action(.timetable), .action(.memoryFragments), .record(.setlist), .action(.companion),
            .record(.merch), .record(.spending), .action(.route), .action(.ticket), .action(.endShow)
        ])
    }

    func testAfterTheShowAnUnfinishedDispersalLeadsBesideTheCompanion() {
        let actions = CurrentShowQuickAction.actions(for: .ended, isPostShowRetention: true)
        let modules = CurrentShowModuleOrder.modules(actions: actions, phase: .ended, timetableIsLive: false)
        XCTAssertEqual(modules, [
            .action(.dispersal(completed: false)), .action(.companion), .action(.memoryFragments), .record(.setlist),
            .record(.merch), .record(.spending), .action(.ticket), .action(.timetable)
        ])
    }

    func testAfterTheShowAFinishedDispersalSinksToTheBottom() {
        let actions = CurrentShowQuickAction.actions(for: .ended, isPostShowRetention: true, hasCompletedDispersalCeremony: true)
        let modules = CurrentShowModuleOrder.modules(actions: actions, phase: .ended, timetableIsLive: false)
        XCTAssertEqual(modules, [
            .action(.memoryFragments), .record(.setlist), .action(.companion),
            .record(.merch), .record(.spending), .action(.ticket), .action(.timetable), .action(.dispersal(completed: true))
        ])
    }

    func testModulesFollowTheGivenActionsWhenNoShowIsOn() {
        let actions = CurrentShowQuickAction.actions(for: .inactive)
        XCTAssertEqual(CurrentShowModuleOrder.modules(actions: actions, phase: .inactive, timetableIsLive: false), actions.map(CurrentShowModule.action))
    }

    // MARK: Grid

    func testHalfCardsPairInOrderAndPullTheNextHalfPastAFullCard() {
        let rows = ShowModuleGridLayout.rows([("a", .half), ("b", .half), ("c", .full), ("d", .half), ("e", .full), ("f", .half)])
        XCTAssertEqual(rows, [.pair("a", "b"), .full("c"), .pair("d", "f"), .full("e")])
    }

    func testALoneHalfCardStretchesInItsOwnPlace() {
        let rows = ShowModuleGridLayout.rows([("a", .full), ("b", .half), ("c", .full)])
        XCTAssertEqual(rows, [.full("a"), .single("b"), .full("c")])
    }

    func testEndedShowDropsRouteFromModules() {
        XCTAssertFalse(CurrentShowQuickAction.actions(for: .ended).contains(.route))
        XCTAssertFalse(CurrentShowQuickAction.actions(for: .ended, isPostShowRetention: true).contains(.route))
    }

    func testMemoryCountReadsTheSameEverywhere() {
        XCTAssertEqual(MemoryMomentTimeline.countText(3), "3 段")
    }
}
