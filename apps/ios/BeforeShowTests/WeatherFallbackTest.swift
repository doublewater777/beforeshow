import SwiftData
import XCTest
import UserNotifications
@testable import BeforeShow

@MainActor
final class WeatherFallbackTest: XCTestCase {
    func testProviderFailureLeavesGenericCalendarReminderUnreplaced() async throws {
        let (container, show, now, calendar) = try makeTomorrowShow()
        let notifications = RecordingWeatherNotifications()
        let provider = StubForecastProvider { throw NSError(domain: "WeatherKit.Error", code: 401) }
        let scheduler = makeScheduler(
            provider: provider,
            notifications: notifications,
            calendar: calendar,
            now: now
        )

        await scheduler.runOpenCheck(modelContext: container.mainContext)

        XCTAssertTrue(notifications.requests.isEmpty, "天气失败时不该另发一条；日历 .oneDayBefore 仍是兜底")
        await scheduler.runOpenCheck(modelContext: container.mainContext)
        XCTAssertEqual(provider.fetchCount, 1, "失败后仍标记已检查，避免反复打 WeatherKit")
        _ = show
    }

    func testComfortableForecastDoesNotReplaceOneDayBefore() async throws {
        let (container, _, now, calendar) = try makeTomorrowShow()
        let notifications = RecordingWeatherNotifications()
        let provider = StubForecastProvider { DailyForecast(
            highCelsius: 25,
            lowCelsius: 15,
            precipitationChance: 0.1,
            precipitationAmountMillimeters: 0,
            windSpeedKilometersPerHour: 10,
            condition: .clear
        ) }
        let scheduler = makeScheduler(
            provider: provider,
            notifications: notifications,
            calendar: calendar,
            now: now
        )

        await scheduler.runOpenCheck(modelContext: container.mainContext)
        XCTAssertTrue(notifications.requests.isEmpty)
        await scheduler.runOpenCheck(modelContext: container.mainContext)
        XCTAssertEqual(provider.fetchCount, 1)
    }

    func testRainReplacesPendingOneDayBeforeWithDeterministicIdentifier() async throws {
        let (container, show, now, calendar) = try makeTomorrowShow()
        let notifications = RecordingWeatherNotifications()
        let provider = StubForecastProvider { DailyForecast(
            highCelsius: 22,
            lowCelsius: 16,
            precipitationChance: 0.4,
            precipitationAmountMillimeters: 8,
            windSpeedKilometersPerHour: 12,
            condition: .rain
        ) }
        let scheduler = makeScheduler(
            provider: provider,
            notifications: notifications,
            calendar: calendar,
            now: now
        )

        await scheduler.runOpenCheck(modelContext: container.mainContext)

        let request = try XCTUnwrap(notifications.requests.first)
        XCTAssertEqual(request.identifier, "\(show.id.uuidString).oneDayBefore")
        XCTAssertEqual(notifications.requests.count, 1)
    }

    func testFailedSubmissionIsNotDeduped() async throws {
        let (container, _, now, calendar) = try makeTomorrowShow()
        let notifications = RecordingWeatherNotifications()
        notifications.error = NSError(domain: "UNError", code: 1)
        let provider = StubForecastProvider { DailyForecast(
            highCelsius: 22,
            lowCelsius: 16,
            precipitationChance: 0.4,
            precipitationAmountMillimeters: 8,
            windSpeedKilometersPerHour: 12,
            condition: .rain
        ) }
        let scheduler = makeScheduler(
            provider: provider,
            notifications: notifications,
            calendar: calendar,
            now: now
        )

        await scheduler.runOpenCheck(modelContext: container.mainContext)
        XCTAssertTrue(notifications.requests.isEmpty)
        notifications.error = nil
        await scheduler.runOpenCheck(modelContext: container.mainContext)
        XCTAssertEqual(notifications.requests.count, 1)
        XCTAssertEqual(provider.fetchCount, 2)
    }

    func testWeatherDoesNotCreateOneDayBeforeForUnscheduledShow() async throws {
        let (container, focused, now, calendar) = try makeTomorrowShow()
        let other = try Show(
            name: "另一场",
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!,
            startTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 21))!,
            city: "杭州",
            venueName: "大麦"
        )
        container.mainContext.insert(other)
        try container.mainContext.save()
        let notifications = RecordingWeatherNotifications()
        let provider = StubForecastProvider { DailyForecast(
            highCelsius: 22,
            lowCelsius: 16,
            precipitationChance: 0.4,
            precipitationAmountMillimeters: 8,
            windSpeedKilometersPerHour: 12,
            condition: .rain
        ) }
        let scheduler = makeScheduler(
            provider: provider,
            notifications: notifications,
            calendar: calendar,
            now: now
        )

        await scheduler.runOpenCheck(modelContext: container.mainContext)

        XCTAssertEqual(notifications.requests.map(\.identifier), ["\(focused.id.uuidString).oneDayBefore"])
    }

    func testInFlightKeyIsStablePerShowAndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let showID = UUID()
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let laterSameDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 19))!
        XCTAssertEqual(
            WeatherReminderScheduler.flightKey(showID: showID, day: day, calendar: calendar),
            WeatherReminderScheduler.flightKey(showID: showID, day: laterSameDay, calendar: calendar)
        )
    }

    private func makeScheduler(
        provider: StubForecastProvider,
        notifications: RecordingWeatherNotifications,
        calendar: Calendar,
        now: Date
    ) -> WeatherReminderScheduler {
        WeatherReminderScheduler(
            provider: provider,
            geocoding: StubGeocoding(),
            deduper: WeatherReminderDeduper(defaults: UserDefaults(suiteName: "weather-test-\(UUID().uuidString)")!),
            calendar: calendar,
            notifications: notifications,
            clock: { now }
        )
    }

    private func makeTomorrowShow() throws -> (ModelContainer, Show, Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 15))!
        let show = try Show(
            name: "上海站",
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!,
            startTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 20))!,
            city: "上海",
            venueName: "梅奔"
        )
        let container = try ModelContainer(
            for: Show.self, ShowNotificationScheduleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.insert(show)
        let fireDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 20))!
        container.mainContext.insert(
            ShowNotificationScheduleRecord(
                showID: show.id,
                milestone: .oneDayBefore,
                fireDate: fireDate,
                title: "明天见",
                body: "上海 明天见，今晚早点休息"
            )
        )
        try container.mainContext.save()
        return (container, show, now, calendar)
    }
}

private struct StubGeocoding: Geocoding {
    func resolve(city: String?, address: String?) async throws -> GeocodedCoordinate? {
        GeocodedCoordinate(latitude: 31.23, longitude: 121.47)
    }
}

private final class StubForecastProvider: WeatherForecastProvider, @unchecked Sendable {
    var fetchCount = 0
    private let fetch: @Sendable () async throws -> DailyForecast?

    init(fetch: @escaping @Sendable () async throws -> DailyForecast?) {
        self.fetch = fetch
    }

    func fetchDailyForecast(at: GeocodedCoordinate, date: Date) async throws -> DailyForecast? {
        fetchCount += 1
        return try await fetch()
    }
}

private final class RecordingWeatherNotifications: WeatherNotificationSubmitting, @unchecked Sendable {
    var requests: [UNNotificationRequest] = []
    var error: Error?

    func add(_ request: UNNotificationRequest) async throws {
        if let error { throw error }
        requests.append(request)
    }
}

