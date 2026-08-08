import SwiftData
import XCTest
@testable import BeforeShow

final class CurrentShowSelectionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 12)
    }

    func testAutomaticSelectionChoosesNearestRelevantUncancelledShow() throws {
        let canceledToday = try makeShow(name: "已取消现场", day: 15)
        canceledToday.markCanceled()
        let expiredPastShow = try makeShow(name: "过了停留期的现场", day: 10)
        let nearestFutureShow = try makeShow(name: "明天的现场", day: 16)
        let laterFutureShow = try makeShow(name: "更远的现场", day: 22)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [laterFutureShow, canceledToday, expiredPastShow, nearestFutureShow],
            now: now
        )

        XCTAssertEqual(selected?.id, nearestFutureShow.id)
    }

    func testRecentlyEndedShowStaysRelevantForPostShowRetentionWindow() throws {
        let recentlyEndedShow = try makeShow(name: "前天结束的现场", day: 13)
        let laterFutureShow = try makeShow(name: "月底现场", day: 30)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [laterFutureShow, recentlyEndedShow],
            now: now
        )

        XCTAssertEqual(selected?.id, recentlyEndedShow.id)
    }

    func testRecentlyEndedShowDoesNotSwitchToNearFutureShowDuringRetentionWindow() throws {
        let recentlyEndedShow = try makeShow(name: "前天结束的现场", day: 13)
        let tomorrowShow = try makeShow(name: "明天的现场", day: 16)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [tomorrowShow, recentlyEndedShow],
            now: now
        )

        XCTAssertEqual(selected?.id, recentlyEndedShow.id)
    }

    func testExpiredEndedShowIsNotCurrentWhenNoRelevantShowExists() throws {
        let expiredPastShow = try makeShow(name: "过了停留期的现场", day: 10)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [expiredPastShow],
            now: now
        )

        XCTAssertNil(selected)
    }

    func testCanceledManualSelectionFallsBackToNearestRelevantShow() throws {
        let canceledShow = try makeShow(name: "已取消现场", day: 16)
        canceledShow.markCanceled()
        let futureShow = try makeShow(name: "仍可准备的现场", day: 20)
        let manualSelection = CurrentShowSelection(selectedShowID: canceledShow.id)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [canceledShow, futureShow],
            manualSelection: manualSelection,
            now: now
        )

        XCTAssertEqual(selected?.id, futureShow.id)
    }

    func testUndatedPostponedManualSelectionFallsBackToNearestRelevantShow() throws {
        let postponedShow = try makeShow(name: "未定延期现场", day: 16)
        postponedShow.markPostponed(newDate: nil)
        let futureShow = try makeShow(name: "仍可准备的现场", day: 20)
        let manualSelection = CurrentShowSelection(selectedShowID: postponedShow.id)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [postponedShow, futureShow],
            manualSelection: manualSelection,
            now: now
        )

        XCTAssertEqual(selected?.id, futureShow.id)
    }

    func testDatedPostponedManualSelectionRemainsEligibleBeforeItsNewDate() throws {
        let postponedShow = try makeShow(name: "已改期现场", day: 10)
        postponedShow.markPostponed(newDate: makeDate(year: 2026, month: 6, day: 20))
        let futureShow = try makeShow(name: "更远现场", day: 25)
        let manualSelection = CurrentShowSelection(selectedShowID: postponedShow.id)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [futureShow, postponedShow],
            manualSelection: manualSelection,
            now: now
        )

        XCTAssertEqual(selected?.id, postponedShow.id)
    }

    func testManualSelectionIsPersistedAndRespected() throws {
        let nearestShow = try makeShow(name: "最近现场", day: 16)
        let manuallySelectedShow = try makeShow(name: "用户手动选中的现场", day: 25)
        let manualSelection = CurrentShowSelection(selectedShowID: manuallySelectedShow.id)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [nearestShow, manuallySelectedShow],
            manualSelection: manualSelection,
            now: now
        )

        XCTAssertEqual(selected?.id, manuallySelectedShow.id)
    }

    @MainActor
    func testManualSelectionModelCanBeStoredLocally() throws {
        let showID = UUID()
        let selection = CurrentShowSelection()
        selection.select(showID: showID)

        let container = try ModelContainer(
            for: CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.insert(selection)
        try container.mainContext.save()

        let selections = try container.mainContext.fetch(FetchDescriptor<CurrentShowSelection>())
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections[0].selectedShowID, showID)
    }

    func testPostponedShowUsesNewDateForAutomaticSelection() throws {
        let postponedShow = try makeShow(name: "延期到明天的现场", day: 10)
        postponedShow.markPostponed(newDate: makeDate(year: 2026, month: 6, day: 16))
        let laterFutureShow = try makeShow(name: "更远现场", day: 20)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [laterFutureShow, postponedShow],
            now: now
        )

        XCTAssertEqual(selected?.id, postponedShow.id)
    }

    func testPostponedShowWithoutNewDateIsNotAutomaticallySelected() throws {
        let postponedShow = try makeShow(name: "未定延期现场", day: 16)
        postponedShow.markPostponed(newDate: nil)
        let laterFutureShow = try makeShow(name: "有日期的现场", day: 20)

        let selected = CurrentShowSelector(calendar: calendar).selectCurrentShow(
            from: [postponedShow, laterFutureShow],
            now: now
        )

        XCTAssertEqual(selected?.id, laterFutureShow.id)
    }

    func testShowRetentionIsTimezoneAware() throws {
        // Show is scheduled for June 15, 2026 at 20:00 UTC.
        // In UTC: Show date is June 15. Retention ends June 18.
        // In Asia/Shanghai (GMT+8): Show date is June 16 (04:00 AM). Retention ends June 19.
        let showDateUTC = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 15, hour: 20
        ).date!
        
        let show = try Show(
            name: "跨时区现场",
            date: showDateUTC,
            startTime: showDateUTC,
            endDate: showDateUTC
        )
        
        // Evaluate at June 19, 2026 at 01:00 UTC.
        let evaluationDate = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 19, hour: 1
        ).date!
        
        // Scenario A: UTC Calendar
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcSelector = CurrentShowSelector(calendar: utcCalendar)
        XCTAssertFalse(utcSelector.isAutomaticallySelectable(show, now: evaluationDate), 
                       "Should be expired in UTC timezone")
        
        // Scenario B: Shanghai Calendar (GMT+8)
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let shanghaiSelector = CurrentShowSelector(calendar: shanghaiCalendar)
        XCTAssertTrue(shanghaiSelector.isAutomaticallySelectable(show, now: evaluationDate), 
                      "Should still be active in Shanghai timezone due to local show date shifting to June 16")
    }

    private func makeShow(name: String, day: Int) throws -> Show {
        try Show(
            name: name,
            date: makeDate(year: 2026, month: 6, day: day),
            startTime: makeDate(year: 2026, month: 6, day: day, hour: 20)
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 20) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
