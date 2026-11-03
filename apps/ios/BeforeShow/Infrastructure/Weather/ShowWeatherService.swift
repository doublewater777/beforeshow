import Foundation
import CoreLocation
import WeatherKit

protocol ShowWeatherServiceProtocol: AnyObject, Sendable {
    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO
    func cachedWeather(for showID: UUID) -> ShowWeatherDTO?
}

private final class ShowWeatherCacheBox: @unchecked Sendable {
    let dto: ShowWeatherDTO
    let expiresAt: Date

    init(dto: ShowWeatherDTO, ttlSeconds: TimeInterval = 1800) {
        self.dto = dto
        self.expiresAt = Date().addingTimeInterval(ttlSeconds)
    }

    var isExpired: Bool {
        Date() > expiresAt
    }
}

final class LiveShowWeatherService: ShowWeatherServiceProtocol, @unchecked Sendable {
    static let shared = LiveShowWeatherService()

    private let cache = NSCache<NSString, ShowWeatherCacheBox>()
    private let geocoder = CLGeocoder()
    private let policy = ShowWeatherAtmospherePolicy()

    init() {}

    func cachedWeather(for showID: UUID) -> ShowWeatherDTO? {
        guard let box = cache.object(forKey: showID.uuidString as NSString), !box.isExpired else {
            return nil
        }
        return box.dto
    }

    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO {
        if let cached = cachedWeather(for: show.id) {
            return cached
        }

        try Task.checkCancellation()

        // 1. 地理编码场地地址或城市
        let location = try await resolveLocation(city: show.city, venueName: show.venueName, venueAddress: show.venueAddress)

        try Task.checkCancellation()

        // 2. WeatherKit 数据获取
        let weather = try await WeatherService.shared.weather(for: location)

        try Task.checkCancellation()

        // 3. 提取 Raw Daily & Hourly Forecast
        let rawDaily = weather.dailyForecast.map { day in
            RawDayForecast(
                date: day.date,
                highCelsius: Int(round(day.highTemperature.converted(to: .celsius).value)),
                lowCelsius: Int(round(day.lowTemperature.converted(to: .celsius).value)),
                condition: mapCondition(from: day.condition),
                conditionDescription: day.condition.description,
                sunsetTime: day.sun.sunset,
                precipitationChance: day.precipitationChance,
                uvIndex: day.uvIndex.value
            )
        }

        let rawHourly = weather.hourlyForecast.map { hour in
            RawHourForecast(
                date: hour.date,
                temperatureCelsius: Int(round(hour.temperature.converted(to: .celsius).value)),
                apparentTemperatureCelsius: Int(round(hour.apparentTemperature.converted(to: .celsius).value)),
                condition: mapCondition(from: hour.condition),
                uvIndex: hour.uvIndex.value,
                windSpeedMps: Int(round(hour.wind.speed.converted(to: .metersPerSecond).value)),
                windDirectionDescription: hour.wind.compassDirection.description
            )
        }

        let eventCalendar = show.timingFields.eventCalendar(fallback: .current)
        let effectiveDate = show.timingFields.effectiveDate
        let startTime = CurrentShowTimeState.dailyStartTime(on: effectiveDate, show: show, calendar: eventCalendar)
        let endTime = CurrentShowTimeState.dailyEndTime(on: effectiveDate, show: show, calendar: eventCalendar)

        let venueEnv = ShowWeatherAtmospherePolicy.resolveVenueEnvironment(
            name: show.name,
            venueName: show.venueName,
            venueAddress: show.venueAddress
        )

        let dto = try policy.resolveForecast(
            for: show.id,
            showDate: effectiveDate,
            showStartTime: startTime,
            showEndTime: endTime,
            calendar: eventCalendar,
            dailyForecasts: rawDaily,
            hourlyForecasts: rawHourly,
            venueEnvironment: venueEnv,
            now: Date()
        )

        try Task.checkCancellation()
        cache.setObject(ShowWeatherCacheBox(dto: dto), forKey: show.id.uuidString as NSString)
        return dto
    }

    private func resolveLocation(city: String?, venueName: String?, venueAddress: String?) async throws -> CLLocation {
        let queryParts = [city, venueName, venueAddress].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !queryParts.isEmpty else {
            throw ShowWeatherError.locationUnavailable
        }
        let query = queryParts.joined(separator: " ")
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let location = placemarks.first?.location else {
            throw ShowWeatherError.locationUnavailable
        }
        return location
    }

    private func mapCondition(from weatherCondition: WeatherKit.WeatherCondition) -> ShowWeatherCondition {
        switch weatherCondition {
        case .clear: return .clear
        case .mostlyClear, .partlyCloudy: return .partlyCloudy
        case .cloudy, .mostlyCloudy: return .cloudy
        case .rain, .drizzle: return .rain
        case .heavyRain, .isolatedThunderstorms, .thunderstorms: return .heavyRain
        case .windy, .breezy: return .windy
        default: return .clear
        }
    }
}

final class MockShowWeatherService: ShowWeatherServiceProtocol, @unchecked Sendable {
    var stubbedWeather: ShowWeatherDTO?
    var shouldThrowError: Error?
    private var cache: [UUID: ShowWeatherDTO] = [:]

    init(stubbedWeather: ShowWeatherDTO? = nil, shouldThrowError: Error? = nil) {
        self.stubbedWeather = stubbedWeather
        self.shouldThrowError = shouldThrowError
    }

    func cachedWeather(for showID: UUID) -> ShowWeatherDTO? {
        stubbedWeather ?? cache[showID]
    }

    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO {
        if let error = shouldThrowError {
            throw error
        }
        if let stubbedWeather {
            return stubbedWeather
        }
        let generated = ShowWeatherDTO(
            showID: show.id,
            temperatureCelsius: 26,
            highCelsius: 28,
            lowCelsius: 20,
            condition: .clear,
            conditionDescription: "晴空晚霞",
            summaryCallout: "演出当天预计 20°~28°。预计 18:34 日落。",
            hourly: [
                ShowWeatherHourlyDTO(time: Date(), temperatureCelsius: 27, condition: .clear, milestoneLabel: "排队入场"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(7200), temperatureCelsius: 28, condition: .partlyCloudy, milestoneLabel: "刺猬乐队"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(14400), temperatureCelsius: 24, condition: .sunset, milestoneLabel: "黄金日落"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(21600), temperatureCelsius: 22, condition: .coldNight, milestoneLabel: "痛仰大合唱"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(28800), temperatureCelsius: 20, condition: .coldNight, milestoneLabel: "散场微风")
            ],
            precipitationProbability: 0.05,
            sunsetTime: Date().addingTimeInterval(14400),
            uvIndex: 6,
            feelsLikeCelsius: 24,
            windDescription: "东南风 3 m/s",
            packingList: [
                ShowWeatherPackingItemDTO(id: "sunglasses", emoji: "🕶️", title: "墨镜、防晒帽", subtitle: "白天日晒较强，注意防晒"),
                ShowWeatherPackingItemDTO(id: "jacket", emoji: "🧥", title: "薄外套", subtitle: "散场预计约 20°C，带件薄外套更稳妥"),
                ShowWeatherPackingItemDTO(id: "water_bottle", emoji: "💧", title: "便携水杯", subtitle: "及时补充水分（入场前请确认场馆携带规定）"),
                ShowWeatherPackingItemDTO(id: "wipes", emoji: "🧻", title: "便携湿巾", subtitle: "长时间观演，带包湿巾更方便")
            ],
            tone: .sunsetGold
        )
        cache[show.id] = generated
        return generated
    }
}
