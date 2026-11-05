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
        let days = ShowWeatherDays.dates(timing: festival.timingFields, calendar: calendar)
        XCTAssertEqual(days, [date(2026, 11, 6), date(2026, 11, 7), date(2026, 11, 8)])

        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 4, 9), calendar: calendar), 0, "before it starts: Day 1")
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 7, 23), calendar: calendar), 1, "while it runs: today")
        XCTAssertEqual(ShowWeatherDays.relevantIndex(of: days, now: date(2026, 11, 10), calendar: calendar), 2, "after it ends: the last day")
    }

    func testASingleNightShowIsOneDay() throws {
        let gig = try Show(name: "专场", date: date(2026, 11, 6), startTime: date(2026, 11, 6, 20), timeZoneIdentifier: "Asia/Shanghai", city: "杭州")
        XCTAssertEqual(ShowWeatherDays.dates(timing: gig.timingFields, calendar: calendar), [date(2026, 11, 6)])
    }

    func testOneChecklistForTheTripSaysWhichDaysNeedWhat() {
        let rain = ShowWeatherPackingItemDTO(id: "rainwear", emoji: "🧥", title: "雨具", subtitle: "可能有降水")
        let water = ShowWeatherPackingItemDTO(id: "water_bottle", emoji: "💧", title: "及时补水", subtitle: "确认场馆规定")
        let days = [
            ShowWeatherDay(index: 1, date: date(2026, 11, 6), weather: weather(packing: [water])),
            ShowWeatherDay(index: 2, date: date(2026, 11, 7), weather: weather(packing: [rain, water])),
            ShowWeatherDay(index: 3, date: date(2026, 11, 8), weather: nil)
        ]
        let list = ShowWeatherDays.packingList(for: days)

        XCTAssertEqual(list.map(\.id), ["water_bottle", "rainwear"])
        XCTAssertEqual(list[0].subtitle, "确认场馆规定", "needed every forecast day: no day label")
        XCTAssertEqual(list[1].subtitle, "Day 2 · 可能有降水")
    }

    // MARK: Helpers

    private func weather(packing: [ShowWeatherPackingItemDTO]) -> ShowWeatherDTO {
        ShowWeatherDTO(
            showID: UUID(), temperatureCelsius: 20, highCelsius: 22, lowCelsius: 15, condition: .cloudy,
            conditionDescription: "多云", summaryCallout: "", hourly: [], precipitationProbability: 0.2,
            sunsetTime: nil, uvIndex: 0, feelsLikeCelsius: 18, windDescription: "--", packingList: packing, tone: .neutral
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
