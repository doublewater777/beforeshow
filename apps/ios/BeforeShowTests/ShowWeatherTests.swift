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
            highCelsius: 28,
            isOutdoor: true
        )
        XCTAssertTrue(list.contains(where: { $0.id == "sunglasses" }))
    }

    func testPackingListRecommendsLightPackForIndoorVenueAndOmitsOutdoorGear() {
        let list = policy.generatePackingList(
            condition: .clear,
            precipitationProbability: 0.05,
            uvIndex: 8,
            lowCelsius: 20,
            highCelsius: 28,
            isOutdoor: false
        )
        XCTAssertTrue(list.contains(where: { $0.id == "light_pack" }))
        XCTAssertFalse(list.contains(where: { $0.id == "sunglasses" }))
        XCTAssertFalse(list.contains(where: { $0.id == "repellent" }))
    }

    func testVenueOutdoorHeuristicsIdentifiesIndoorAndOutdoor() {
        XCTAssertFalse(ShowWeatherAtmospherePolicy.isLikelyOutdoorVenue(name: "专场演出", venueName: "LiveShop Uni 由你现场", venueAddress: "杭州拱墅区"))
        XCTAssertFalse(ShowWeatherAtmospherePolicy.isLikelyOutdoorVenue(name: "巡演", venueName: "MAO Livehouse", venueAddress: "上海"))
        XCTAssertTrue(ShowWeatherAtmospherePolicy.isLikelyOutdoorVenue(name: "草莓音乐节", venueName: "大梅沙海滨公园", venueAddress: "深圳"))
        XCTAssertTrue(ShowWeatherAtmospherePolicy.isLikelyOutdoorVenue(name: "露天摇滚夜", venueName: "市民广场", venueAddress: "北京"))
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

    func testSummaryCalloutInterpolatesTemperaturesCorrectly() throws {
        let summary = policy.generateSummary(
            conditionDesc: "晴",
            sunsetTime: nil,
            high: 28,
            low: 19
        )
        XCTAssertTrue(summary.contains("19°~28°"), "Expected summary to contain formatted temperature range, got: \(summary)")
    }

    func testTimelineRunsFromSettingOffToGettingHomeOnALongFestivalDay() throws {
        let calendar = Calendar.current
        let showDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: Date())!)
        let start = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: showDate)!
        let end = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: showDate)!
        let day = RawDayForecast(
            date: showDate, highCelsius: 25, lowCelsius: 16, condition: .clear, conditionDescription: "晴",
            sunsetTime: calendar.date(bySettingHour: 17, minute: 30, second: 0, of: showDate), precipitationChance: 0, uvIndex: 3
        )
        let hours = (0..<24).map { hour in
            RawHourForecast(
                date: calendar.date(byAdding: .hour, value: hour, to: showDate)!,
                temperatureCelsius: 20, apparentTemperatureCelsius: 20, condition: .clear,
                uvIndex: 0, windSpeedMps: 1, windDirectionDescription: ""
            )
        }

        let result = try policy.resolveForecast(
            for: UUID(), showDate: showDate, showStartTime: start, showEndTime: end,
            calendar: calendar, dailyForecasts: [day], hourlyForecasts: hours, now: Date()
        )

        XCTAssertEqual(result.hourly.first?.time, showDate, "the whole day, from setting off in the morning")
        XCTAssertEqual(result.hourly.last?.time, calendar.date(bySettingHour: 23, minute: 0, second: 0, of: showDate), "to the last hour of the day, getting home included")
        XCTAssertTrue(result.hourly.contains { $0.milestoneLabel == BSLocalization.text("散场") }, "a long day is no longer cut before it ends")
    }

    func testForecastWithoutMatchingWindowHoursDegradesGracefullyWithoutFakeHourly() throws {
        let calendar = Calendar.current
        let showDate = calendar.date(byAdding: .day, value: 2, to: Date())!
        let showStartTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: showDate)!
        let showEndTime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: showDate)!

        let dayForecast = RawDayForecast(
            date: showDate,
            highCelsius: 27,
            lowCelsius: 16,
            condition: .clear,
            conditionDescription: "晴朗",
            sunsetTime: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: showDate),
            precipitationChance: 0.0,
            uvIndex: 4
        )
        // Morning-only hour (08:00), unrelated to night show window (18:00-24:00)
        let morningHour = RawHourForecast(
            date: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: showDate)!,
            temperatureCelsius: 17,
            apparentTemperatureCelsius: 17,
            condition: .cloudy,
            uvIndex: 1,
            windSpeedMps: 1,
            windDirectionDescription: "北风"
        )

        let result = try policy.resolveForecast(
            for: UUID(),
            showDate: showDate,
            showStartTime: showStartTime,
            showEndTime: showEndTime,
            calendar: calendar,
            dailyForecasts: [dayForecast],
            hourlyForecasts: [morningHour],
            now: Date()
        )

        // Must NOT use the 08:00 morning hour as show weather; hourly must be empty and temperature falls back to day high
        XCTAssertTrue(result.hourly.isEmpty)
        XCTAssertEqual(result.temperatureCelsius, 27)
        XCTAssertEqual(result.condition, .clear)
    }
    func testVenueAndJacketAdviceAvoidUnsupportedAssumptions() throws {
        XCTAssertEqual(ShowWeatherAtmospherePolicy.resolveVenueEnvironment(name: "音乐节", venueName: "大剧院", venueAddress: nil), .indoor)
        XCTAssertEqual(ShowWeatherAtmospherePolicy.resolveVenueEnvironment(name: "音乐节", venueName: nil, venueAddress: nil), .unspecified)
        let list = policy.generatePackingList(condition: .clear, precipitationProbability: 0, uvIndex: 8, lowCelsius: 15, highCelsius: 27, dispersalCelsius: 16, dispersalFeelsLike: 14, venueEnvironment: .unspecified)
        XCTAssertTrue(try XCTUnwrap(list.first { $0.id == "jacket" }).subtitle.contains("14°C"))
        XCTAssertFalse(list.contains { $0.id == "sunglasses" })
        let warm = policy.generatePackingList(condition: .clear, precipitationProbability: 0, uvIndex: 1, lowCelsius: 15, highCelsius: 27, dispersalCelsius: 16, dispersalFeelsLike: 23)
        XCTAssertFalse(warm.contains { $0.id == "jacket" })
    }

    func testWeatherNotificationRequiresFreshForecastNearDelivery() {
        let now = Date()
        let weather = ShowWeatherDTO(showID: UUID(), fetchedAt: now, temperatureCelsius: 20, highCelsius: 25, lowCelsius: 16, condition: .rain, conditionDescription: "雨", summaryCallout: "", hourly: [], precipitationProbability: 0.8, showPeriodPrecipitationProbability: 0.8, sunsetTime: nil, uvIndex: 1, feelsLikeCelsius: 20, windDescription: "--", packingList: [], tone: .rainBlue)
        XCTAssertNotNil(LocalNotificationScheduler.weatherTip(weather, now: now, fireDate: now.addingTimeInterval(1800)))
        XCTAssertNil(LocalNotificationScheduler.weatherTip(weather, now: now, fireDate: now.addingTimeInterval(1801)))
        XCTAssertNil(LocalNotificationScheduler.weatherTip(weather, now: now.addingTimeInterval(1801), fireDate: now.addingTimeInterval(1801)))
    }

    func testShowPeriodRainAdviceUsesHourlyForecastNotDailyRain() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let end = start.addingTimeInterval(7200)
        let day = RawDayForecast(date: start, highCelsius: 25, lowCelsius: 20, condition: .rain, conditionDescription: "雨", sunsetTime: nil, precipitationChance: 0.9, uvIndex: 0)
        func hour(_ chance: Double) -> RawHourForecast {
            RawHourForecast(date: start, temperatureCelsius: 23, apparentTemperatureCelsius: 23, condition: .clear, uvIndex: 0, windSpeedMps: 1, windDirectionDescription: "", precipitationChance: chance)
        }
        func resolve(_ hours: [RawHourForecast]) throws -> ShowWeatherDTO {
            try policy.resolveForecast(for: UUID(), showDate: start, showStartTime: start, showEndTime: end, calendar: .current, dailyForecasts: [day], hourlyForecasts: hours, now: start.addingTimeInterval(-3600))
        }
        let dry = try resolve([hour(0.05)])
        XCTAssertEqual(dry.precipitationProbability, 0.9)
        XCTAssertFalse(dry.packingList.contains { $0.id == "rainwear" })
        XCTAssertNil(LocalNotificationScheduler.weatherTip(dry, now: dry.fetchedAt, fireDate: dry.fetchedAt))
        let wet = try resolve([hour(0.8)])
        XCTAssertTrue(wet.packingList.contains { $0.id == "rainwear" })
        XCTAssertNotNil(LocalNotificationScheduler.weatherTip(wet, now: wet.fetchedAt, fireDate: wet.fetchedAt))
        let unavailable = try resolve([])
        XCTAssertFalse(unavailable.packingList.contains { $0.id == "rainwear" })
        XCTAssertNil(LocalNotificationScheduler.weatherTip(unavailable, now: unavailable.fetchedAt, fireDate: unavailable.fetchedAt))
    }

    func testForecastCarriesEventTimeZoneAndFormatsSunsetThere() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 20)))
        let sunset = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 17, minute: 3)))
        let day = RawDayForecast(date: start, highCelsius: 20, lowCelsius: 15, condition: .clear, conditionDescription: "晴", sunsetTime: sunset, precipitationChance: 0, uvIndex: 1)
        let result = try policy.resolveForecast(for: UUID(), showDate: start, showStartTime: start, showEndTime: start.addingTimeInterval(7200), calendar: calendar, dailyForecasts: [day], hourlyForecasts: [], now: start.addingTimeInterval(-86400))
        XCTAssertEqual(result.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertTrue(result.summaryCallout.contains("17:03"))
    }

    func testWeatherCalendarUsesVenueTimeZoneWhenShowHasNone() throws {
        let now = Date()
        var timing = ShowTimingFields(date: now, startTime: now, endDate: nil, endTime: nil, postponedDate: nil, changeStatus: .scheduled)
        var fallback = Calendar(identifier: .gregorian)
        fallback.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertEqual(try policy.weatherCalendar(timing: timing, locationTimeZone: shanghai, fallback: fallback).timeZone.identifier, "Asia/Shanghai")
        XCTAssertThrowsError(try policy.weatherCalendar(timing: timing, locationTimeZone: nil, fallback: fallback))
        timing.timeZoneIdentifier = "Europe/London"
        XCTAssertEqual(try policy.weatherCalendar(timing: timing, locationTimeZone: shanghai, fallback: fallback).timeZone.identifier, "Europe/London")
    }

}
