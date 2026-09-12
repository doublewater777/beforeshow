import XCTest
@testable import BeforeShow

final class MemoryFragmentRelativeTimeBoundaryTests: XCTestCase {
    func testSubHourRelativeTimeSurvivesMidnightBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 0, minute: 4))
        )
        let fiveMinutesAgo = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 23, minute: 59))
        )

        XCTAssertEqual(
            MemoryFragmentRelativeTime.format(fiveMinutesAgo, now: now, calendar: calendar),
            "5 分钟前"
        )
    }

    func testYesterdayLabelAppliesAfterRelativeMinuteWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 0, minute: 4))
        )
        let earlierYesterday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 22, minute: 59))
        )

        XCTAssertEqual(
            MemoryFragmentRelativeTime.format(earlierYesterday, now: now, calendar: calendar),
            "昨天 22:59"
        )
    }
}
