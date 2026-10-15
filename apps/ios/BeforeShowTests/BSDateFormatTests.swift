import XCTest
@testable import BeforeShow

final class BSDateFormatTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testClockIsTwentyFourHourInTheEventTimeZone() {
        XCTAssertEqual(BSDateFormat.clock(date(2026, 10, 15, 19, 30), timeZone: shanghai), "19:30")
        XCTAssertEqual(BSDateFormat.clock(date(2026, 10, 15, 0, 5), timeZone: shanghai), "00:05")
        XCTAssertEqual(BSDateFormat.clock(date(2026, 10, 15, 19, 30), timeZone: TimeZone(identifier: "Europe/London")!), "12:30")
    }

    func testDottedDateUsesTheShowCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        XCTAssertEqual(BSDateFormat.dottedDate(date(2026, 3, 7, 23, 30), calendar: calendar), "2026.03.07")
    }

    func testDateTimeStaysTwentyFourHourInTwelveHourLocales() {
        let text = BSDateFormat.dateTime(date(2026, 10, 15, 19, 30), timeZone: shanghai, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("19:30"), text)
        XCTAssertFalse(text.contains("PM"), text)
        XCTAssertTrue(text.contains("Oct"), text)

        let chinese = BSDateFormat.dateTime(date(2026, 10, 15, 19, 30), timeZone: shanghai, locale: Locale(identifier: "zh_Hans_CN"))
        XCTAssertTrue(chinese.contains("19:30"), chinese)
        XCTAssertFalse(chinese.contains("下午"), chinese)
    }
}
