import XCTest
@testable import BeforeShow

final class ShowDurationFormatterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testSingleFormatsHoursAndMinutes() {
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 19, 30), to: day(2026, 8, 15, 21, 48)),
            "2 小时 18 分"
        )
    }

    func testSingleFormatsWholeHours() {
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 19, 0), to: day(2026, 8, 15, 22, 0)),
            "3 小时"
        )
    }

    func testSingleFormatsSubHourAsMinutes() {
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 19, 0), to: day(2026, 8, 15, 19, 45)),
            "45 分钟"
        )
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 19, 0), to: day(2026, 8, 15, 19, 0).addingTimeInterval(30)),
            "1 分钟"
        )
    }

    func testSingleUsesDaysBeyond24Hours() {
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 13, 0), to: day(2026, 8, 17, 23, 0)),
            "2 天 10 小时"
        )
        XCTAssertEqual(
            ShowDurationFormatter.single(from: day(2026, 8, 15, 13, 0), to: day(2026, 8, 17, 13, 0)),
            "2 天"
        )
    }

    func testSingleReturnsNilWhenEndNotAfterStart() {
        let start = day(2026, 8, 15, 19, 0)
        XCTAssertNil(ShowDurationFormatter.single(from: start, to: start))
        XCTAssertNil(ShowDurationFormatter.single(from: start, to: day(2026, 8, 15, 18, 0)))
    }

    func testAggregateUsesHoursBelowThreshold() {
        XCTAssertEqual(ShowDurationFormatter.aggregate(totalMinutes: 82 * 60), "82 小时")
        XCTAssertEqual(ShowDurationFormatter.aggregate(totalMinutes: 0), "0 小时")
    }

    func testAggregateUsesDaysBeyondThreshold() {
        XCTAssertEqual(ShowDurationFormatter.aggregate(totalMinutes: 110 * 60), "4 天 14 小时")
        XCTAssertEqual(ShowDurationFormatter.aggregate(totalMinutes: 120 * 60), "5 天")
    }

    func testMinutesForShowPrefersConfirmedEnd() throws {
        let show = try Show(name: "测试现场", date: day(2026, 8, 15), startTime: day(2026, 8, 15, 19, 30))
        show.markEnded(at: day(2026, 8, 15, 22, 0))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 8, 16))
        XCTAssertEqual(ShowDurationFormatter.minutes(for: show, timeState: state), 150)
    }

    func testMinutesForShowDoesNotCountEstimatedDuration() throws {
        let show = try Show(name: "测试现场", date: day(2026, 8, 15), startTime: day(2026, 8, 15, 19, 30))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))
        XCTAssertNil(ShowDurationFormatter.minutes(for: show, timeState: state))
    }

    func testHistoricalShowCountsItsRecordedEndWithoutASeparateCurtainConfirmation() throws {
        let show = try Show(name: "补录现场", date: day(2026, 8, 15),
                            startTime: day(2026, 8, 15, 19, 30), endTime: day(2026, 8, 15, 22))
        show.markAddedAsHistorical()
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))

        XCTAssertNil(show.endedAt)
        XCTAssertEqual(ShowDurationFormatter.minutes(for: show, timeState: state), 150)
    }

    func testConfirmedMultiDayShowCountsEveryDayWithoutOvernightBreaks() throws {
        let show = try Show(name: "三日音乐节", date: day(2026, 8, 15),
                            startTime: day(2026, 8, 15, 13), endDate: day(2026, 8, 17),
                            endTime: day(2026, 8, 15, 22), timeZoneIdentifier: "Asia/Shanghai")
        show.markEnded(at: day(2026, 8, 17, 21, 30))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))

        XCTAssertEqual(ShowDurationFormatter.minutes(for: show, timeState: state), (9 + 9) * 60 + 8 * 60 + 30)
    }

    func testHistoricalShowWithoutAnEndDoesNotInventViewingTime() throws {
        let show = try Show(name: "结束未知", date: day(2026, 8, 15), startTime: day(2026, 8, 15, 19))
        show.markAddedAsHistorical()
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))

        XCTAssertNil(ShowDurationFormatter.minutes(for: show, timeState: state))
    }

    func testMultiDayOvernightSessionsExcludeTheDaytimeBreaks() throws {
        let show = try Show(name: "午夜音乐节", date: day(2026, 8, 15),
                            startTime: day(2026, 8, 15, 22), endDate: day(2026, 8, 17),
                            endTime: day(2026, 8, 16, 1), timeZoneIdentifier: "Asia/Shanghai")
        show.markEnded(at: day(2026, 8, 18, 1, 30))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))

        XCTAssertEqual(ShowDurationFormatter.minutes(for: show, timeState: state), 9 * 60 + 30)
    }

    func testTimetableDurationSkipsRestDaysAndDoesNotDoubleCountParallelStages() throws {
        let show = try Show(name: "有休演日的音乐节", date: day(2026, 8, 15),
                            startTime: day(2026, 8, 15, 13), endDate: day(2026, 8, 17))
        let firstStage = try TimetableStage(name: "主舞台", performances: [
            TimetablePerformance(artistName: "A", startsAt: day(2026, 8, 15, 13), endsAt: day(2026, 8, 15, 18))
        ])
        let parallelStage = try TimetableStage(name: "副舞台", performances: [
            TimetablePerformance(artistName: "B", startsAt: day(2026, 8, 15, 16), endsAt: day(2026, 8, 15, 22))
        ])
        let lastStage = try TimetableStage(name: "主舞台", performances: [
            TimetablePerformance(artistName: "C", startsAt: day(2026, 8, 17, 14), endsAt: day(2026, 8, 17, 21))
        ])
        show.timetable = try Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDay(date: day(2026, 8, 15), stages: [firstStage, parallelStage]),
            TimetableDay(date: day(2026, 8, 17), stages: [lastStage])
        ])
        show.markEnded(at: day(2026, 8, 17, 21, 30))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))

        XCTAssertEqual(ShowDurationFormatter.minutes(for: show, timeState: state), 16 * 60 + 30)
    }

    @MainActor
    func testArchiveIncludesHistoricalRecordedTimeAndAllFestivalDays() throws {
        let historical = try Show(name: "补录单场", date: day(2026, 8, 10),
                                  startTime: day(2026, 8, 10, 19, 30), endTime: day(2026, 8, 10, 22))
        historical.markAddedAsHistorical()
        let festival = try Show(name: "三日现场", date: day(2026, 8, 15),
                                startTime: day(2026, 8, 15, 13), endDate: day(2026, 8, 17),
                                endTime: day(2026, 8, 15, 22), timeZoneIdentifier: "Asia/Shanghai")
        festival.markEnded(at: day(2026, 8, 17, 22))
        let archive = FootprintArchiveBuilder.make(shows: [historical, festival], now: day(2026, 9, 1), calendar: calendar)

        XCTAssertEqual(archive.totalDurationMinutes, 150 + 27 * 60)
        XCTAssertEqual(archive.yearActivity(for: 2026)?.months[7].durationMinutes, 150 + 27 * 60)
    }

    @MainActor
    func testArchiveBuilderSumsDurationsAcrossShows() throws {
        let confirmed = try Show(name: "已确认散场", date: day(2026, 8, 15), startTime: day(2026, 8, 15, 19, 30))
        confirmed.markEnded(at: day(2026, 8, 15, 22, 0))
        let estimated = try Show(name: "无结束时间", date: day(2026, 8, 10), startTime: day(2026, 8, 10, 20, 0))
        let canceled = try Show(name: "已取消", date: day(2026, 8, 12), startTime: day(2026, 8, 12, 20, 0))
        canceled.markCanceled()

        let archive = FootprintArchiveBuilder.make(
            shows: [confirmed, estimated, canceled],
            now: day(2026, 9, 1),
            calendar: calendar
        )

        XCTAssertEqual(archive.shows.count, 2)
        XCTAssertEqual(archive.totalDurationMinutes, 150)
    }
}
