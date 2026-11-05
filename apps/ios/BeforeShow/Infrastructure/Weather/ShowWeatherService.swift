import Foundation
import CoreLocation
import WeatherKit

protocol ShowWeatherServiceProtocol: AnyObject, Sendable {
    /// The forecast for the day that matters now: today while a multi-day show runs, else its next day.
    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO
    /// Every day of the show, each with its own forecast when the forecast reaches it.
    @MainActor
    func fetchWeatherDays(for show: Show) async throws -> [ShowWeatherDay]
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

/// One WeatherKit answer for a place, reused for every day of the same show.
private final class ShowWeatherRawBox: @unchecked Sendable {
    let daily: [RawDayForecast]
    let hourly: [RawHourForecast]
    let timeZone: TimeZone?
    let expiresAt = Date().addingTimeInterval(1800)

    init(daily: [RawDayForecast], hourly: [RawHourForecast], timeZone: TimeZone?) {
        self.daily = daily
        self.hourly = hourly
        self.timeZone = timeZone
    }
}

final class LiveShowWeatherService: ShowWeatherServiceProtocol, @unchecked Sendable {
    static let shared = LiveShowWeatherService()

    private let cache = NSCache<NSString, ShowWeatherCacheBox>()
    private let rawCache = NSCache<NSString, ShowWeatherRawBox>()
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
        let days = try await fetchWeatherDays(for: show)
        let relevant = ShowWeatherDays.relevantIndex(of: days, now: Date())
        guard let dto = days.indices.contains(relevant) ? days[relevant].weather ?? days.compactMap(\.weather).first : nil else {
            throw ShowWeatherError.forecastUnavailable
        }
        // A multi-day show moves on to its next day at the venue's midnight, whatever the TTL says.
        var venueCalendar = Calendar(identifier: .gregorian)
        venueCalendar.timeZone = days[relevant].timeZone
        let midnight = venueCalendar.date(byAdding: .day, value: 1, to: venueCalendar.startOfDay(for: Date()))
        let ttl = min(1800, midnight.map { $0.timeIntervalSinceNow } ?? 1800)
        cache.setObject(ShowWeatherCacheBox(dto: dto, ttlSeconds: days.count > 1 ? ttl : 1800), forKey: show.id.uuidString as NSString)
        return dto
    }

    @MainActor
    func fetchWeatherDays(for show: Show) async throws -> [ShowWeatherDay] {
        let raw = try await rawForecast(for: show)
        try Task.checkCancellation()

        let eventCalendar = try policy.weatherCalendar(
            timing: show.timingFields, locationTimeZone: raw.timeZone, fallback: .current
        )
        let venueEnv = ShowWeatherAtmospherePolicy.resolveVenueEnvironment(
            name: show.name,
            venueName: show.venueName,
            venueAddress: show.venueAddress
        )
        let now = Date()
        return ShowWeatherDays.slots(timing: show.timingFields, calendar: eventCalendar).enumerated().map { offset, slot in
            // A day the forecast doesn't reach yet stays in the list without weather.
            let dto = try? policy.resolveForecast(
                for: show.id,
                showDate: slot.date,
                showStartTime: slot.start,
                showEndTime: slot.end,
                calendar: eventCalendar,
                dailyForecasts: raw.daily,
                hourlyForecasts: raw.hourly,
                venueEnvironment: venueEnv,
                now: now
            )
            return ShowWeatherDay(index: offset + 1, date: slot.date, weather: dto, timeZone: eventCalendar.timeZone, start: slot.start, end: slot.end)
        }
    }

    @MainActor
    private func rawForecast(for show: Show) async throws -> ShowWeatherRawBox {
        let key = show.id.uuidString as NSString
        if let cached = rawCache.object(forKey: key), Date() < cached.expiresAt {
            return cached
        }
        try Task.checkCancellation()

        // 1. 地理编码场地地址或城市
        let placemark = try await resolveLocation(city: show.city, venueName: show.venueName, venueAddress: show.venueAddress)
        guard let location = placemark.location else { throw ShowWeatherError.locationUnavailable }

        try Task.checkCancellation()

        // 2. WeatherKit 数据获取
        let weather = try await WeatherService.shared.weather(for: location)

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
                windDirectionDescription: hour.wind.compassDirection.description,
                precipitationChance: hour.precipitationChance,
                conditionDescription: hour.condition.description
            )
        }
        let box = ShowWeatherRawBox(daily: rawDaily, hourly: rawHourly, timeZone: placemark.timeZone)
        rawCache.setObject(box, forKey: key)
        return box
    }

    private func resolveLocation(city: String?, venueName: String?, venueAddress: String?) async throws -> CLPlacemark {
        let queryParts = [city, venueName, venueAddress].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !queryParts.isEmpty else {
            throw ShowWeatherError.locationUnavailable
        }
        let query = queryParts.joined(separator: " ")
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let placemark = placemarks.first, placemark.location != nil else {
            throw ShowWeatherError.locationUnavailable
        }
        return placemark
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

    @MainActor
    func fetchWeatherDays(for show: Show) async throws -> [ShowWeatherDay] {
        let timing = show.timingFields
        let calendar = timing.eventCalendar(fallback: .current)
        let slot = ShowWeatherDays.slots(timing: timing, calendar: calendar)[0]
        return [ShowWeatherDay(index: 1, date: slot.date, weather: try await fetchWeather(for: show), timeZone: calendar.timeZone, start: slot.start, end: slot.end)]
    }
}
