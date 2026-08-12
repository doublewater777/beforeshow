import SwiftData
import XCTest
@testable import BeforeShow

final class ShowModelTests: XCTestCase {
    @MainActor
    func testShowCanBeCreatedAndStoredWithOnlyNameAndDate() throws {
        let date = Date(timeIntervalSince1970: 1_779_552_000)
        let startTime = Date(timeIntervalSince1970: 1_779_555_600)
        let show = try Show(
            name: "落日飞车 北京站",
            date: date,
            startTime: startTime,
            coverImageURL: "https://example.com/cover.jpg",
            artistAvatarURLs: ["https://example.com/artist.jpg"]
        )

        let container = try ModelContainer(
            for: Show.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.insert(show)
        try container.mainContext.save()

        let shows = try container.mainContext.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows[0].name, "落日飞车 北京站")
        XCTAssertEqual(shows[0].date, date)
        XCTAssertEqual(shows[0].startTime, startTime)
        XCTAssertNil(shows[0].venueName)
        XCTAssertEqual(shows[0].coverImageURL, "https://example.com/cover.jpg")
        XCTAssertEqual(shows[0].artistAvatarURLs, ["https://example.com/artist.jpg"])
    }

    func testPostponedAndCanceledAreRepresentedWithoutGenericAbnormalStates() throws {
        let show = try Show(name: "延期测试现场", date: Date(), startTime: Date())

        show.markPostponed(newDate: nil)
        XCTAssertEqual(show.changeStatus, .postponed)
        XCTAssertNil(show.postponedDate)

        let newDate = Date(timeIntervalSinceNow: 86_400)
        show.markPostponed(newDate: newDate)
        XCTAssertEqual(show.changeStatus, .postponed)
        XCTAssertEqual(show.postponedDate, newDate)

        show.markCanceled()
        XCTAssertEqual(show.changeStatus, .canceled)

        XCTAssertEqual(ShowChangeStatus.allCases, [.scheduled, .postponed, .canceled])
    }

    @MainActor
    func testShowStoresOptionalEndDateAndEndTime() throws {
        let container = try ModelContainer(
            for: Show.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let startDate = Date(timeIntervalSince1970: 1_783_468_800)
        let startTime = Date(timeIntervalSince1970: 1_783_551_600)
        let endDate = Date(timeIntervalSince1970: 1_783_555_200)
        let endTime = Date(timeIntervalSince1970: 1_783_558_800)
        let show = try Show(
            name: "深夜发光 Livehouse",
            date: startDate,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime
        )

        container.mainContext.insert(show)
        try container.mainContext.save()

        let storedShow = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(storedShow.endDate, endDate)
        XCTAssertEqual(storedShow.endTime, endTime)
    }

    func testInvalidEndDateBeforeStartDateIsRejected() {
        XCTAssertThrowsError(try Show(
            name: "错误时间现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 7, day: 7, hour: 0, minute: 0, calendar: .current),
            endTime: makeDate(year: 2026, month: 7, day: 7, hour: 22, minute: 0, calendar: .current)
        )) { error in
            XCTAssertEqual(error as? ShowValidationError, .invalidEndTime)
        }
    }

    func testCurrentShowTimeStateMovesStartTimeOntoPostponedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let originalDate = makeDate(year: 2026, month: 6, day: 10, hour: 0, minute: 0, calendar: calendar)
        let originalStartTime = makeDate(year: 2026, month: 6, day: 10, hour: 19, minute: 30, calendar: calendar)
        let postponedDate = makeDate(year: 2026, month: 6, day: 16, hour: 0, minute: 0, calendar: calendar)
        let show = try Show(
            name: "延期但保留开场时间的现场",
            date: originalDate,
            startTime: originalStartTime
        )

        show.markPostponed(newDate: postponedDate)

        let state = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0, calendar: calendar)
        )

        XCTAssertEqual(state.kind, .before)
        XCTAssertEqual(state.statusText, "已延期")
        XCTAssertEqual(state.countdownText, "还有 1 天")
        XCTAssertEqual(state.effectiveDate, postponedDate)
        XCTAssertEqual(
            state.effectiveStartTime,
            makeDate(year: 2026, month: 6, day: 16, hour: 19, minute: 30, calendar: calendar)
        )
    }

    func testCrossDayLivehouseUsesActualEndTimeForCountdownAndRetention() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "深夜发光 Livehouse",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 0, calendar: calendar)
        )

        let beforeStart = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(beforeStart.kind, .today)
        XCTAssertEqual(beforeStart.countdownText, "还有 3 小时")

        let beforeEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(beforeEnd.kind, .today)
        XCTAssertEqual(beforeEnd.countdownText, "正在现场")

        let afterEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(afterEnd.kind, .postShow)
        XCTAssertEqual(afterEnd.helperText, "7月9日 01:00 结束 · 停留期还剩 2 天 23 小时")

        let afterRetention = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 12, hour: 2, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(afterRetention.kind, .ended)
    }

    func testMissingEndTimeUsesStartPlusTypeDurationAsStateBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Concert default: start 19:30 + 4h → end boundary 23:30
        let show = try Show(
            name: "未填结束时间的现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 19, minute: 30, calendar: calendar)
        )

        XCTAssertNil(show.endTime)
        XCTAssertEqual(CurrentShowTimeState.defaultDurationHours, 4)

        let beforeFallbackEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(beforeFallbackEnd.kind, .today)
        XCTAssertEqual(beforeFallbackEnd.countdownText, "正在现场")

        let afterFallbackEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 31, calendar: calendar)
        )
        XCTAssertEqual(afterFallbackEnd.kind, .postShow)
        XCTAssertTrue(afterFallbackEnd.helperText.contains("23:30"))
    }

    func testConfirmedEndOverridesEstimatedBoundaryAndCanBeUndone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "确认散场的现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 19, minute: 30, calendar: calendar)
        )
        let confirmedEnd = makeDate(
            year: 2026,
            month: 7,
            day: 8,
            hour: 22,
            minute: 10,
            calendar: calendar
        )

        show.markEnded(at: confirmedEnd)

        let endedState = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 20, calendar: calendar)
        )
        XCTAssertEqual(endedState.kind, .postShow)
        XCTAssertEqual(endedState.endBoundary, confirmedEnd)
        XCTAssertEqual(endedState.effectiveEndTime, confirmedEnd)

        show.clearEnded()

        let resumedState = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 20, calendar: calendar)
        )
        XCTAssertEqual(resumedState.kind, .today)
        XCTAssertNil(show.endedAt)
    }

    func testMultiDayDailyCycleEndsEachDayAndRestartsNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 8/15–17，每日 13:00–22:00（共用 endTime）
        let show = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 8, day: 15, hour: 22, minute: 0, calendar: calendar)
        )

        XCTAssertTrue(CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar))

        let middleMorning = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 16, hour: 10, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(middleMorning.kind, .today)
        XCTAssertEqual(middleMorning.countdownText, "还有 3 小时")
        XCTAssertEqual(
            middleMorning.effectiveStartTime,
            makeDate(year: 2026, month: 8, day: 16, hour: 13, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(
            middleMorning.endBoundary,
            makeDate(year: 2026, month: 8, day: 16, hour: 22, minute: 0, calendar: calendar)
        )

        let middleLive = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 16, hour: 15, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(middleLive.kind, .today)
        XCTAssertEqual(middleLive.countdownText, "正在现场")
        XCTAssertEqual(
            HomeShowPhase(
                timeState: middleLive,
                now: makeDate(year: 2026, month: 8, day: 16, hour: 15, minute: 0, calendar: calendar)
            ),
            .live
        )

        let middleNight = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 16, hour: 23, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(middleNight.kind, .dayEnded)
        XCTAssertEqual(middleNight.countdownText, "今日已落幕")
        XCTAssertEqual(middleNight.helperText, "明天 13:00 再开")
        XCTAssertEqual(middleNight.title, "今日已落幕")
        XCTAssertTrue(middleNight.isAutomaticallySelectable)
        XCTAssertEqual(
            HomeShowPhase(timeState: middleNight).kickerText(city: "上海", timeState: middleNight),
            "今日已落幕"
        )

        let lastLive = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 17, hour: 14, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(lastLive.kind, .today)
        XCTAssertEqual(lastLive.countdownText, "正在现场")

        let afterLast = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 17, hour: 23, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(afterLast.kind, .postShow)
        XCTAssertTrue(afterLast.helperText.contains("8月17日 22:00 结束"))

        let noEndClock = try Show(
            name: "三日音乐节",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: calendar)
        )
        let day1AfterDefaultEnd = CurrentShowTimeState(
            show: noEndClock,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 15, hour: 18, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(day1AfterDefaultEnd.kind, .dayEnded)
        XCTAssertEqual(
            day1AfterDefaultEnd.endBoundary,
            makeDate(year: 2026, month: 8, day: 15, hour: 17, minute: 0, calendar: calendar)
        )
    }

    func testShowDisplayFormatterFormatsCrossDayAndMultiDayRanges() throws {
        let crossDay = try Show(
            name: "深夜发光 Livehouse",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 0, calendar: .current),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 0, calendar: .current)
        )
        let multiDay = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: .current)
        )
        let multiDayWithEnd = try Show(
            name: "绿洲音乐节晚场",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: .current),
            endTime: makeDate(year: 2026, month: 8, day: 15, hour: 22, minute: 0, calendar: .current)
        )
        let noEndTime = try Show(
            name: "普通演唱会",
            date: makeDate(year: 2026, month: 9, day: 12, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 9, day: 12, hour: 19, minute: 30, calendar: .current)
        )
        let formatter = ShowDisplayFormatter()

        XCTAssertEqual(formatter.dateText(for: crossDay), "2026年7月8日 23:00 - 7月9日 01:00")
        XCTAssertEqual(formatter.dateText(for: multiDay), "2026年8月15日-17日 · 每日 13:00")
        XCTAssertEqual(formatter.dateText(for: multiDayWithEnd), "2026年8月15日-17日 · 每日 13:00-22:00")
        XCTAssertEqual(formatter.dateText(for: noEndTime), "2026年9月12日 19:30")
    }

    func testShowDisplayFormatterUsesEndOffsetAcrossDSTBoundary() throws {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let startDay = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let start = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        let end = ISO8601DateFormatter().date(from: "2026-11-01T02:30:00-08:00")!
        let show = try Show(
            name: "DST 边界现场",
            date: startDay,
            startTime: start,
            endDate: end,
            endTime: end,
            timeZoneSecondsFromGMT: -7 * 3_600,
            endTimeZoneSecondsFromGMT: -8 * 3_600
        )

        XCTAssertEqual(
            ShowDisplayFormatter(calendar: pacific).dateText(for: show),
            "2026年11月1日 01:30 - 02:30"
        )
    }

    func testShowDisplayFormatterUsesVenueLocalDateOnDeviceInAnotherTimeZone() throws {
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = ISO8601DateFormatter().date(from: "2026-09-17T02:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-09-17T05:00:00Z")!
        let show = try Show(
            name: "异地现场",
            date: start,
            startTime: start,
            endDate: end,
            endTime: end,
            timeZoneSecondsFromGMT: -7 * 3_600,
            endTimeZoneSecondsFromGMT: -7 * 3_600
        )

        XCTAssertEqual(
            ShowDisplayFormatter(calendar: deviceCalendar).dateText(for: show),
            "2026年9月16日 19:00 - 22:00"
        )
    }

    func testIANAEventTimeZoneKeepsPostponedClockAcrossDST() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let originalDate = losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        let originalStart = ISO8601DateFormatter().date(from: "2026-09-17T02:00:00Z")!
        let postponedDate = losAngeles.date(from: DateComponents(year: 2026, month: 12, day: 16))!
        let show = try Show(
            name: "跨夏令时延期现场",
            date: originalDate,
            startTime: originalStart,
            timeZoneSecondsFromGMT: -7 * 3_600,
            timeZoneIdentifier: "America/Los_Angeles"
        )

        show.markPostponed(newDate: postponedDate)

        XCTAssertEqual(
            CurrentShowTimeState.effectiveStartTime(for: show, calendar: Calendar(identifier: .gregorian)),
            ISO8601DateFormatter().date(from: "2026-12-17T03:00:00Z")!
        )
    }

    func testMultiDayEndClockUsesEndEventCalendarAcrossDSTBoundary() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let start = ISO8601DateFormatter().date(from: "2026-11-01T02:00:00Z")!
        let endDate = losAngeles.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let endTime = ISO8601DateFormatter().date(from: "2026-11-03T06:00:00Z")!
        let show = try Show(
            name: "跨夏令时多日现场",
            date: date,
            startTime: start,
            endDate: endDate,
            endTime: endTime,
            timeZoneSecondsFromGMT: -7 * 3_600,
            endTimeZoneSecondsFromGMT: -8 * 3_600,
            timeZoneIdentifier: "America/Los_Angeles",
            endTimeZoneIdentifier: "America/Los_Angeles"
        )

        XCTAssertEqual(
            CurrentShowTimeState.dailyEndTime(on: endDate, show: show, calendar: Calendar(identifier: .gregorian)),
            endTime
        )
    }

    func testFixedOffsetEndDateUsesEndLocalDayForMultiDayCycle() throws {
        var startCalendar = Calendar(identifier: .gregorian)
        startCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 3_600)!
        var endCalendar = Calendar(identifier: .gregorian)
        endCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        let date = startCalendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let start = startCalendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 19))!
        let endDate = endCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let endTime = endCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30))!
        let show = try Show(
            name: "固定时区跨日现场",
            date: date,
            startTime: start,
            endDate: endDate,
            endTime: endTime,
            timeZoneSecondsFromGMT: -7 * 3_600,
            endTimeZoneSecondsFromGMT: -8 * 3_600
        )

        let state = CurrentShowTimeState(show: show, calendar: startCalendar, now: endTime.addingTimeInterval(-30 * 60))

        XCTAssertTrue(CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: startCalendar))
        XCTAssertEqual(startCalendar.component(.day, from: try XCTUnwrap(state.effectiveEndDate)), 1)
        XCTAssertTrue(
            CurrentShowEndPolicy.canRecordEnd(
                show: show,
                timeState: state,
                now: endTime.addingTimeInterval(-30 * 60),
                calendar: Calendar(identifier: .gregorian)
            )
        )
    }

    func testMultiDayOvernightSessionsKeepPreviousDayAcrossMidnightAndAnchorConfirmedEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "跨午夜音乐节",
            date: makeDate(year: 2026, month: 8, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 10, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 8, day: 8, hour: 1, minute: 0, calendar: calendar)
        )
        let middleMidnight = makeDate(year: 2026, month: 8, day: 9, hour: 0, minute: 30, calendar: calendar)
        let middleState = CurrentShowTimeState(show: show, calendar: calendar, now: middleMidnight)
        XCTAssertEqual(middleState.kind, .today)
        XCTAssertEqual(middleState.effectiveStartTime, makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar))
        XCTAssertEqual(middleState.effectiveEndTime, makeDate(year: 2026, month: 8, day: 9, hour: 1, minute: 0, calendar: calendar))

        let confirmedEnd = makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 30, calendar: calendar)
        XCTAssertEqual(
            CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: calendar),
            makeDate(year: 2026, month: 8, day: 10, hour: 22, minute: 0, calendar: calendar)
        )
        show.markEnded(at: confirmedEnd)
        let endedState = CurrentShowTimeState(show: show, calendar: calendar, now: confirmedEnd.addingTimeInterval(60))
        XCTAssertEqual(endedState.effectiveStartTime, makeDate(year: 2026, month: 8, day: 10, hour: 22, minute: 0, calendar: calendar))
        XCTAssertEqual(endedState.effectiveEndTime, confirmedEnd)
    }

    func testFutureMultiDayCycleUsesFirstSessionAndFinalBoundaryBeforeStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "未来音乐节",
            date: makeDate(year: 2026, month: 8, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 10, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 8, day: 8, hour: 1, minute: 0, calendar: calendar)
        )
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: makeDate(year: 2026, month: 8, day: 1, hour: 10, minute: 0, calendar: calendar))
        XCTAssertEqual(state.kind, .before)
        XCTAssertEqual(state.effectiveStartTime, makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar))
        XCTAssertEqual(state.effectiveEndTime, makeDate(year: 2026, month: 8, day: 9, hour: 1, minute: 0, calendar: calendar))
        XCTAssertEqual(state.endBoundary, makeDate(year: 2026, month: 8, day: 11, hour: 1, minute: 0, calendar: calendar))
    }

    func testEditingMultiDayEndDateClearsConfirmedEndBeforeNewFinalSession() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "修改范围现场",
            date: makeDate(year: 2026, month: 8, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 10, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 8, day: 8, hour: 1, minute: 0, calendar: calendar)
        )
        show.markEnded(at: makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 30, calendar: calendar))
        var draft = ShowDraft(show: show)
        draft.endDate = makeDate(year: 2026, month: 8, day: 12, hour: 0, minute: 0, calendar: calendar)
        try show.apply(draft)
        XCTAssertNil(show.endedAt)
    }

    func testShowCoverFallbackUsesSplashImageWithoutMissingCoverCopy() {
        let presentation = ShowCoverFallbackPresentation(reason: .noCover)

        XCTAssertEqual(presentation.assetName, "splash_bg")
        XCTAssertEqual(presentation.alignment, .top)
        XCTAssertTrue(presentation.visibleTexts.isEmpty)
    }

    func testTodayPhaseUsesTodayKind() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "今晚现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: calendar)
        )
        let state = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 12, minute: 0, calendar: calendar)
        )

        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.title, "今天开场")
    }

    func testEditingStartIntoFutureClearsStaleConfirmedEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let originalStart = makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: calendar)
        let confirmedEnd = makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 0, calendar: calendar)
        let show = try Show(name: "改期现场", date: originalStart, startTime: originalStart)
        show.markEnded(at: confirmedEnd)

        var draft = ShowDraft(show: show)
        let futureStart = makeDate(year: 2026, month: 7, day: 10, hour: 20, minute: 0, calendar: calendar)
        draft.date = futureStart
        draft.startTime = futureStart
        try show.apply(draft)

        XCTAssertNil(show.endedAt)
    }

    func testEditingWithoutInvalidatingConfirmedEndPreservesIt() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let confirmedEnd = start.addingTimeInterval(7_200)
        let show = try Show(name: "保留真实散场", date: start, startTime: start)
        show.markEnded(at: confirmedEnd)

        var draft = ShowDraft(show: show)
        draft.name = "只改名称"
        try show.apply(draft)

        XCTAssertEqual(show.endedAt, confirmedEnd)
    }

    func testPostponingOrCancelingClearsConfirmedEnd() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "状态变化现场", date: start, startTime: start)

        show.markEnded(at: start.addingTimeInterval(7_200))
        show.markPostponed(newDate: start.addingTimeInterval(86_400))
        XCTAssertNil(show.endedAt)

        show.markScheduled()
        show.markEnded(at: start.addingTimeInterval(7_200))
        show.markCanceled()
        XCTAssertNil(show.endedAt)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
