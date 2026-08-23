import Foundation
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

    func testMinutesForShowFallsBackToDefaultEstimateWithoutEndTime() throws {
        let show = try Show(name: "测试现场", date: day(2026, 8, 15), startTime: day(2026, 8, 15, 19, 30))
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: day(2026, 9, 1))
        XCTAssertEqual(
            ShowDurationFormatter.minutes(for: show, timeState: state),
            CurrentShowTimeState.defaultDurationHours * 60
        )
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
        XCTAssertEqual(archive.totalDurationMinutes, 150 + CurrentShowTimeState.defaultDurationHours * 60)
    }

    func testCountdownDynamicLocalizationDoesNotLeakSourceKeys() {
        let suiteName = "CountdownLocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("en", forKey: "appLanguage")
        XCTAssertEqual(BSLocalization.testFallback("距离开场", localeIdentifier: "en"), "Until show starts")
        XCTAssertEqual(BSLocalization.testFallback("小时", localeIdentifier: "en"), "hours")
        XCTAssertEqual(BSLocalization.testFallback("分钟", localeIdentifier: "en"), "minutes")
        XCTAssertEqual(BSLocalization.testFallback("秒", localeIdentifier: "en"), "seconds")

        defaults.set("zh-Hant", forKey: "appLanguage")
        XCTAssertEqual(BSLocalization.testFallback("距离开场", localeIdentifier: "zh-Hant"), "距離開場")
        XCTAssertEqual(BSLocalization.testFallback("小时", localeIdentifier: "zh-Hant"), "小時")
        XCTAssertEqual(BSLocalization.testFallback("分钟", localeIdentifier: "zh-Hant"), "分鐘")
        XCTAssertEqual(BSLocalization.testFallback("秒", localeIdentifier: "zh-Hant"), "秒")
    }
}
