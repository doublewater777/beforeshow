import XCTest
@testable import BeforeShow

final class ShowWeatherTests: XCTestCase {
    private let policy = ShowWeatherAtmospherePolicy()

    func testRainyWeatherResolvesRainBlueTone() {
        let tone = policy.resolveTone(condition: .rain)
        XCTAssertEqual(tone, .rainBlue)

        let heavyTone = policy.resolveTone(condition: .heavyRain)
        XCTAssertEqual(heavyTone, .rainBlue)
    }

    func testSunsetWeatherResolvesSunsetGoldTone() {
        let tone = policy.resolveTone(condition: .sunset)
        XCTAssertEqual(tone, .sunsetGold)
    }

    func testNearSunsetTimeResolvesSunsetGoldTone() {
        let sunset = Date()
        let tone = policy.resolveTone(
            condition: .clear,
            now: sunset.addingTimeInterval(1800), // 30 mins after sunset
            sunsetTime: sunset
        )
        XCTAssertEqual(tone, .sunsetGold)
    }

    func testColdNightResolvesColdNightIndigoTone() {
        let tone = policy.resolveTone(condition: .coldNight)
        XCTAssertEqual(tone, .coldNightIndigo)
    }

    func testPackingListRecommendsRainwearOnHighPrecipitation() {
        let list = policy.generatePackingList(
            condition: .rain,
            precipitationProbability: 0.65,
            uvIndex: 2,
            lowCelsius: 19,
            highCelsius: 22
        )
        XCTAssertTrue(list.contains(where: { $0.id == "rainwear" }))
    }

    func testPackingListRecommendsSunglassesOnHighUV() {
        let list = policy.generatePackingList(
            condition: .clear,
            precipitationProbability: 0.05,
            uvIndex: 7,
            lowCelsius: 20,
            highCelsius: 28
        )
        XCTAssertTrue(list.contains(where: { $0.id == "sunglasses" }))
    }

    func testPackingListRecommendsJacketOnLargeTemperatureDifferential() {
        let list = policy.generatePackingList(
            condition: .clear,
            precipitationProbability: 0.0,
            uvIndex: 4,
            lowCelsius: 14,
            highCelsius: 24 // 10 degree drop
        )
        XCTAssertTrue(list.contains(where: { $0.id == "jacket" }))
    }

    func testForecastResolutionMatchesShowDateAndNotCurrentDate() throws {
        let calendar = Calendar.current
        let today = Date()
        let showDate = calendar.date(byAdding: .day, value: 3, to: today)!
        let showStartTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: showDate)!
        let showEndTime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: showDate)!

        let todayForecast = RawDayForecast(
            date: today,
            highCelsius: 32,
            lowCelsius: 24,
            condition: .heavyRain,
            conditionDescription: "大暴雨",
            sunsetTime: calendar.date(bySettingHour: 18, minute: 10, second: 0, of: today),
            precipitationChance: 0.9,
            uvIndex: 1
        )
        let showDayForecast = RawDayForecast(
            date: showDate,
            highCelsius: 25,
            lowCelsius: 18,
            condition: .clear,
            conditionDescription: "晴天",
            sunsetTime: calendar.date(bySettingHour: 18, minute: 20, second: 0, of: showDate),
            precipitationChance: 0.05,
            uvIndex: 5
        )

        let hour1 = RawHourForecast(
            date: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: showDate)!,
            temperatureCelsius: 23,
            apparentTemperatureCelsius: 23,
            condition: .clear,
            uvIndex: 2,
            windSpeedMps: 2,
            windDirectionDescription: "东风"
        )
        let hour2 = RawHourForecast(
            date: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: showDate)!,
            temperatureCelsius: 22,
            apparentTemperatureCelsius: 22,
            condition: .clear,
            uvIndex: 0,
            windSpeedMps: 2,
            windDirectionDescription: "东风"
        )

        let result = try policy.resolveForecast(
            for: UUID(),
            showDate: showDate,
            showStartTime: showStartTime,
            showEndTime: showEndTime,
            calendar: calendar,
            dailyForecasts: [todayForecast, showDayForecast],
            hourlyForecasts: [hour1, hour2],
            now: today
        )

        // Must match show day (25/18, clear), NOT today (32/24, heavyRain)
        XCTAssertEqual(result.highCelsius, 25)
        XCTAssertEqual(result.lowCelsius, 18)
        XCTAssertEqual(result.condition, .clear)
        XCTAssertEqual(result.conditionDescription, "晴天")
        XCTAssertEqual(result.temperatureCelsius, 22) // Uses showStartTime hour (19:00), not now
    }

    func testForecastResolutionThrowsWhenOutOfRange() {
        let calendar = Calendar.current
        let today = Date()
        let showDate = calendar.date(byAdding: .day, value: 20, to: today)!
        let showStartTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: showDate)!
        let showEndTime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: showDate)!

        let todayForecast = RawDayForecast(
            date: today,
            highCelsius: 30,
            lowCelsius: 22,
            condition: .clear,
            conditionDescription: "晴",
            sunsetTime: nil,
            precipitationChance: 0.0,
            uvIndex: 4
        )

        XCTAssertThrowsError(
            try policy.resolveForecast(
                for: UUID(),
                showDate: showDate,
                showStartTime: showStartTime,
                showEndTime: showEndTime,
                calendar: calendar,
                dailyForecasts: [todayForecast],
                hourlyForecasts: [],
                now: today
            )
        ) { error in
            XCTAssertEqual(error as? ShowWeatherError, .forecastUnavailable)
        }
    }

    @MainActor
    func testMockWeatherServiceThrowsWhenConfigured() async throws {
        let show = try Show(
            name: "不止音乐节",
            date: Date(),
            startTime: Date(),
            city: "深圳",
            venueName: "大梅沙海滨公园"
        )
        let service = MockShowWeatherService(shouldThrowError: ShowWeatherError.forecastUnavailable)

        do {
            _ = try await service.fetchWeather(for: show)
            XCTFail("Expected fetchWeather to throw error")
        } catch {
            XCTAssertEqual(error as? ShowWeatherError, .forecastUnavailable)
        }
    }

    @MainActor
    func testMockWeatherServiceReturnsStubbedDTO() async throws {
        let show = try Show(
            name: "不止音乐节",
            date: Date(),
            startTime: Date(),
            city: "深圳",
            venueName: "大梅沙海滨公园"
        )
        let service = MockShowWeatherService()
        let weather = try await service.fetchWeather(for: show)

        XCTAssertEqual(weather.temperatureCelsius, 26)
        XCTAssertEqual(weather.tone, .sunsetGold)
        XCTAssertEqual(service.cachedWeather(for: show.id)?.showID, show.id)
    }

    func testNotificationCopyWeatherIntegration() throws {
        let show = try Show(
            name: "草莓音乐节",
            date: Date(),
            startTime: Date(),
            city: "深圳",
            venueName: "大梅沙海滨公园"
        )
        let calendar = Calendar.current
        let timeState = CurrentShowTimeState(show: show, calendar: calendar, now: Date())
        let copy = NotificationCopy(
            context: NotificationCopyContext(show: show, timeState: timeState, calendar: calendar)
        )

        let oneDayCopy = copy.oneDayBefore(
            hasDisc: false,
            isWanted: false,
            weatherTip: "现场有雨，记得备好雨衣。"
        )
        XCTAssertTrue(oneDayCopy.contains("现场有雨，记得备好雨衣。"))

        let showDayCopy = copy.showDay(
            remainingSeconds: nil,
            hasMusic: false,
            weatherTip: "气温 26°，适合观演。"
        )
        XCTAssertTrue(showDayCopy.contains("气温 26°，适合观演。"))

        let sunsetCopy = copy.showDay(
            remainingSeconds: nil,
            hasMusic: false,
            sunsetArtist: "刺猬乐队"
        )
        XCTAssertTrue(sunsetCopy.contains("今天的日落现场是刺猬乐队。"))
    }

    func testFindSunsetPerformanceMatchesPlayingBand() throws {
        let baseDate = Date()
        let cal = Calendar.current
        let sunset = cal.date(bySettingHour: 18, minute: 30, second: 0, of: baseDate)!

        let p1 = try TimetablePerformance(
            artistName: "开场乐队",
            startsAt: cal.date(bySettingHour: 15, minute: 0, second: 0, of: baseDate)!,
            endsAt: cal.date(bySettingHour: 15, minute: 40, second: 0, of: baseDate)!
        )
        let pSunset = try TimetablePerformance(
            artistName: "落日飞车",
            startsAt: cal.date(bySettingHour: 18, minute: 10, second: 0, of: baseDate)!,
            endsAt: cal.date(bySettingHour: 18, minute: 55, second: 0, of: baseDate)!
        )
        let pNight = try TimetablePerformance(
            artistName: "压轴压台",
            startsAt: cal.date(bySettingHour: 20, minute: 30, second: 0, of: baseDate)!,
            endsAt: cal.date(bySettingHour: 21, minute: 30, second: 0, of: baseDate)!
        )

        let matched = policy.findSunsetPerformance(in: [p1, pSunset, pNight], sunsetTime: sunset)
        XCTAssertEqual(matched?.artistName, "落日飞车")

        // No sunset match for a late night performance
        let lateSunset = cal.date(bySettingHour: 17, minute: 0, second: 0, of: baseDate)!
        let noneMatched = policy.findSunsetPerformance(in: [pNight], sunsetTime: lateSunset)
        XCTAssertNil(noneMatched)
    }

    func testWeatherDetailDeepLinkAndSheetID() {
        XCTAssertEqual(NotificationDeepLink.Destination.weatherDetail.rawValue, "weatherDetail")
        XCTAssertEqual(CurrentShowPresentedSheet.weatherDetail.id, "weatherDetail")
    }

    func testWeatherDetailDeepLinkFromURL() {
        let url = URL(string: "beforeshow://show/detail?sheet=weather")!
        let link = NotificationDeepLink(url: url)
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.destination, .weatherDetail)
    }

    func testWeatherDetailDeepLinkFromUserInfoWithURL() {
        let userInfo: [AnyHashable: Any] = [
            "url": "beforeshow://show/detail?sheet=weather"
        ]
        let link = NotificationDeepLink(userInfo: userInfo)
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.destination, .weatherDetail)
    }

    func testLocalNotificationSchedulerWithoutCachedSunsetWeatherDoesNotAppendBand() throws {
        let calendar = Calendar.current
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let startTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: baseDate)!
        let show = try Show(name: "夜场演出", date: baseDate, startTime: startTime)

        let pSunset = try TimetablePerformance(
            artistName: "落日飞车",
            startsAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: baseDate)!,
            endsAt: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: baseDate)!
        )
        let stage = try TimetableStage(name: "Main", performances: [pSunset])
        let day = try TimetableDay(date: baseDate, stages: [stage])
        show.timetable = try Timetable(timeZoneIdentifier: calendar.timeZone.identifier, days: [day])

        // Without cached weather sunset, requests must not guess 18:30
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: baseDate)!
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now)
        let showDayRequest = requests.first(where: { $0.milestone == .showDay })
        XCTAssertNotNil(showDayRequest)
        XCTAssertFalse(showDayRequest?.body.contains("今天的日落现场是") == true)
    }
}
