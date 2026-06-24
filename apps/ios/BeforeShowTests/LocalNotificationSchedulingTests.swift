import SwiftData
import XCTest
@testable import BeforeShow

final class LocalNotificationSchedulingTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 10)
    }

    func testPermissionIsRequestedOnlyAfterUserHasAddedShow() {
        let policy = NotificationPermissionPolicy()

        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: false,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertTrue(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .authorized,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: true
        ))
    }

    func testMissedMilestonesAreNotBackfilledWhenShowIsAddedLate() throws {
        let show = try Show(
            name: "夏夜演唱会",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20),
            type: .concert
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        XCTAssertEqual(requests.map(\.milestone), [.oneDayBefore, .showDay])
        XCTAssertEqual(requests.map(\.fireDate), [
            makeDate(year: 2026, month: 6, day: 19, hour: 20),
            makeDate(year: 2026, month: 6, day: 20, hour: 17)
        ])
    }

    func testShowDayReminderFallsBackToNoonWhenStartTimeIsMissing() throws {
        let show = try Show(
            name: "没有开场时间的现场",
            date: makeDate(year: 2026, month: 6, day: 20),
            type: .livehouse
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: makeDate(year: 2026, month: 6, day: 1)
        )

        XCTAssertEqual(
            requests.first(where: { $0.milestone == .showDay })?.fireDate,
            makeDate(year: 2026, month: 6, day: 20, hour: 12)
        )
    }

    func testPostponedShowDayReminderUsesNewDateWithOriginalStartClock() throws {
        let show = try Show(
            name: "延期保留开场时间的现场",
            date: makeDate(year: 2026, month: 6, day: 10),
            startTime: makeDate(year: 2026, month: 6, day: 10, hour: 19),
            type: .concert
        )
        show.markPostponed(newDate: makeDate(year: 2026, month: 6, day: 25, hour: 0))

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: makeDate(year: 2026, month: 6, day: 1)
        )

        XCTAssertEqual(requests.map(\.milestone), [.fourteenDaysBefore, .oneDayBefore, .showDay])
        XCTAssertEqual(requests.map(\.fireDate), [
            makeDate(year: 2026, month: 6, day: 11, hour: 20),
            makeDate(year: 2026, month: 6, day: 24, hour: 20),
            makeDate(year: 2026, month: 6, day: 25, hour: 16)
        ])
    }

    func testCanceledAndUndatedPostponedShowsDoNotScheduleNotifications() throws {
        let canceled = try Show(
            name: "取消现场",
            date: makeDate(year: 2026, month: 6, day: 25),
            type: .concert
        )
        canceled.markCanceled()

        let postponedWithoutNewDate = try Show(
            name: "未定延期现场",
            date: makeDate(year: 2026, month: 6, day: 25),
            type: .concert
        )
        postponedWithoutNewDate.markPostponed(newDate: nil)

        let scheduler = LocalNotificationScheduler(calendar: calendar)

        XCTAssertEqual(scheduler.futureRequests(for: canceled, now: now), [])
        XCTAssertEqual(scheduler.futureRequests(for: postponedWithoutNewDate, now: now), [])
    }

    func testChangingCurrentShowClearsOldFutureRecordsAndSchedulesNewFocus() throws {
        let oldShowID = UUID()
        let oldRecord = ShowNotificationScheduleRecord(
            showID: oldShowID,
            milestone: .oneDayBefore,
            fireDate: makeDate(year: 2026, month: 6, day: 18, hour: 20)
        )
        let expiredOldRecord = ShowNotificationScheduleRecord(
            showID: oldShowID,
            milestone: .fourteenDaysBefore,
            fireDate: makeDate(year: 2026, month: 6, day: 1, hour: 20)
        )
        let newShow = try Show(
            name: "新的当前现场",
            date: makeDate(year: 2026, month: 6, day: 25),
            startTime: makeDate(year: 2026, month: 6, day: 25, hour: 19),
            type: .musicFestival
        )

        let plan = LocalNotificationScheduler(calendar: calendar).planFocusChange(
            from: [oldRecord, expiredOldRecord],
            to: newShow,
            now: now
        )

        XCTAssertEqual(plan.recordsToCancel.map(\.id), [oldRecord.id])
        XCTAssertEqual(Set(plan.requestsToSchedule.map(\.showID)), [newShow.id])
        XCTAssertEqual(
            plan.requestsToSchedule.map(\.milestone),
            [.oneDayBefore, .showDay]
        )
    }

    @MainActor
    func testNotificationSchedulingStateCanBeStoredLocally() throws {
        let showID = UUID()
        let state = NotificationSchedulingState()
        state.recordPermissionRequest()
        state.focus(showID: showID)
        let record = ShowNotificationScheduleRecord(
            showID: showID,
            milestone: .showDay,
            fireDate: makeDate(year: 2026, month: 6, day: 20, hour: 12)
        )

        let container = try ModelContainer(
            for: NotificationSchedulingState.self, ShowNotificationScheduleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(state)
        container.mainContext.insert(record)
        try container.mainContext.save()

        let states = try container.mainContext.fetch(FetchDescriptor<NotificationSchedulingState>())
        let records = try container.mainContext.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())

        XCTAssertEqual(states.first?.focusedShowID, showID)
        XCTAssertEqual(states.first?.hasRequestedPermissionAfterFirstShow, true)
        XCTAssertEqual(records.first?.milestone, .showDay)
    }

    func testNotificationSchedulingIsTimezoneAware() throws {
        // Show is at June 25, 2026 at 20:00 UTC.
        let showDateUTC = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 25, hour: 20
        ).date!
        
        let show = try Show(name: "跨时区通知现场", date: showDateUTC, type: .concert)
        
        // Scenario A: UTC Calendar
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcScheduler = LocalNotificationScheduler(calendar: utcCalendar)
        let utcRequests = utcScheduler.futureRequests(for: show, now: now)
        
        if let utcT1 = utcRequests.first(where: { $0.milestone == .oneDayBefore }) {
            // T-1 should be June 24 at 20:00 UTC
            let expectedUTCFireDate = DateComponents(
                calendar: utcCalendar,
                timeZone: utcCalendar.timeZone,
                year: 2026, month: 6, day: 24, hour: 20
            ).date!
            XCTAssertEqual(utcT1.fireDate, expectedUTCFireDate, "T-1 fire date should match UTC local hour")
        } else {
            XCTFail("Should find T-1 notification in UTC")
        }
        
        // Scenario B: Shanghai Calendar (GMT+8)
        // June 25 at 20:00 UTC is June 26 at 04:00 AM in Shanghai.
        // Therefore, T-1 should be June 25 at 20:00 Shanghai time (which is June 25 at 12:00 UTC).
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let shanghaiScheduler = LocalNotificationScheduler(calendar: shanghaiCalendar)
        let shanghaiRequests = shanghaiScheduler.futureRequests(for: show, now: now)
        
        if let shanghaiT1 = shanghaiRequests.first(where: { $0.milestone == .oneDayBefore }) {
            let expectedShanghaiFireDate = DateComponents(
                calendar: shanghaiCalendar,
                timeZone: shanghaiCalendar.timeZone,
                year: 2026, month: 6, day: 25, hour: 20
            ).date!
            XCTAssertEqual(shanghaiT1.fireDate, expectedShanghaiFireDate, "T-1 fire date should match Shanghai local hour")
        } else {
            XCTFail("Should find T-1 notification in Shanghai")
        }
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
