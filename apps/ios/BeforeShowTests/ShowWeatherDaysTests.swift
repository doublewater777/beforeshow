import XCTest
@testable import BeforeShow

@MainActor
final class ShowWeatherDaysTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testAMultiDayFestivalCoversEveryDayAndOpensOnTheOneThatMatters() throws {
        let festival = try Show(
            name: "橘子湾", date: date(2026, 11, 6), startTime: date(2026, 11, 6, 13), endDate: date(2026, 11, 8),
            endTime: date(2026, 11, 8, 22), timeZoneIdentifier: "Asia/Shanghai", city: "福州"
        )
        let days = ShowWeatherDays.slots(timing: festival.timingFields, calendar: calendar).map(\.date)
        XCTAssertEqual(days, [date(2026, 11, 6), date(2026, 11, 7), date(2026, 11, 8)])

        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 4, 9), calendar: calendar), 0, "before it starts: Day 1")
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 7, 23), calendar: calendar), 1, "while it runs: today")
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 10), calendar: calendar), 2, "after it ends: the last day")
    }

    func testASingleNightShowIsOneDay() throws {
        let gig = try Show(name: "专场", date: date(2026, 11, 6), startTime: date(2026, 11, 6, 20), timeZoneIdentifier: "Asia/Shanghai", city: "杭州")
        XCTAssertEqual(ShowWeatherDays.slots(timing: gig.timingFields, calendar: calendar).map(\.date), [date(2026, 11, 6)])
    }

    func testAFestivalWithATimetableCoversEachDayItPlays() {
        let timing = ShowTimingFields(
            date: date(2026, 11, 6), startTime: date(2026, 11, 6, 13), endDate: date(2026, 11, 9), endTime: date(2026, 11, 9, 22),
            timeZoneIdentifier: "Asia/Shanghai",
            sessions: [
                ShowSessionTiming(date: date(2026, 11, 6), startsAt: date(2026, 11, 6, 13), endsAt: date(2026, 11, 6, 22)),
                ShowSessionTiming(date: date(2026, 11, 7), startsAt: date(2026, 11, 7, 14), endsAt: date(2026, 11, 8, 1)),
                ShowSessionTiming(date: date(2026, 11, 9), startsAt: date(2026, 11, 9, 12), endsAt: date(2026, 11, 9, 22))
            ],
            postponedDate: nil, changeStatus: .scheduled
        )
        let slots = ShowWeatherDays.slots(timing: timing, calendar: calendar)

        XCTAssertEqual(slots.map(\.date), [date(2026, 11, 6), date(2026, 11, 7), date(2026, 11, 9)], "a skipped day is left out")
        XCTAssertEqual(slots[1].start, date(2026, 11, 7, 14))
        XCTAssertEqual(slots[1].end, date(2026, 11, 8, 1), "a set past midnight stays on its day")
    }

    func testTheDayToOpenOnIsReadOnTheVenueCalendarNotThePhones() {
        var venue = Calendar(identifier: .gregorian)
        venue.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let first = venue.date(from: DateComponents(year: 2026, month: 11, day: 6))!
        let second = venue.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let days = [first, second].enumerated().map {
            ShowWeatherDay(index: $0.offset + 1, date: $0.element, weather: nil, timeZone: venue.timeZone, start: $0.element, end: $0.element)
        }
        // Nov 7 08:00 in Shanghai is still Nov 6 at the venue.
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 7, 8)), 0)
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 7, 18)), 1)
    }

    func testTheShowBandFollowsTheShowsOwnTimesEvenWhenSunsetTakesTheLabel() {
        let hours = (12...23).map { date(2026, 11, 6, $0) }
        let band = ShowWeatherDays.showBand(hours: hours, start: date(2026, 11, 6, 15), end: date(2026, 11, 6, 17, 30))
        XCTAssertEqual(band, 3...5, "15:00 to 17:30 covers the 15, 16 and 17 o'clock hours, not the rest of the night")
    }

    func testOneChecklistForTheTripSaysWhichDaysNeedWhat() {
        let rain = ShowWeatherPackingItemDTO(id: "rainwear", emoji: "🧥", title: "雨具", subtitle: "可能有降水")
        let water = ShowWeatherPackingItemDTO(id: "water_bottle", emoji: "💧", title: "及时补水", subtitle: "确认场馆规定")
        let days = [
            day(1, date(2026, 11, 6), weather(packing: [water])),
            day(2, date(2026, 11, 7), weather(packing: [rain, water])),
            day(3, date(2026, 11, 8))
        ]
        let list = ShowWeatherDays.packingList(for: days)

        XCTAssertEqual(list.map(\.id), ["water_bottle", "rainwear"])
        XCTAssertEqual(list[0].subtitle, "确认场馆规定", "needed every forecast day: no day label")
        XCTAssertEqual(list[1].subtitle, "Day 2 · 可能有降水")
    }

    // MARK: Helpers

    private func day(_ index: Int, _ date: Date, _ weather: ShowWeatherDTO? = nil) -> ShowWeatherDay {
        ShowWeatherDay(index: index, date: date, weather: weather, timeZone: calendar.timeZone, start: date, end: date)
    }

    private func weather(packing: [ShowWeatherPackingItemDTO]) -> ShowWeatherDTO {
        ShowWeatherDTO(
            showID: UUID(), temperatureCelsius: 20, highCelsius: 22, lowCelsius: 15, condition: .cloudy,
            conditionDescription: "多云", summaryCallout: "", hourly: [], precipitationProbability: 0.2,
            sunsetTime: nil, uvIndex: 0, feelsLikeCelsius: 18, windDescription: "--", packingList: packing, tone: .neutral
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
