import Foundation
import CoreLocation
import WeatherKit

enum WeatherKitLegalAttribution {
    static func legalPageURL() async -> URL? {
        try? await WeatherService.shared.attribution.legalPageURL
    }
}

struct WeatherKitForecastProvider: WeatherForecastProvider {
    /// 前置条件（必须做，不然 simulator 真机都拿不到数据）：
    /// 1. App ID `com.doublewaterapps.beforeshow` 在 Apple Developer Portal 的
    ///    `Identifiers → App IDs → App Services` 里勾选 **WeatherKit** 能力。
    ///    没有勾选时 WeatherService.weather(for:) 抛
    ///    `WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2`
    ///    （JWT 拿不到）。
    /// 2. 付费 Apple Developer Program 账号（500,000 calls/月 免费额度）。
    ///
    /// 没满足时：scheduler 的兜底会把 forecast 当 nil 处理，照样发"明天见"，
    /// 不会有 weather-specific 内容。模拟器对 Cupertino 等预设坐标返回合成数据，
    /// 不依赖真接口；真机要真数据必须先在 Apple Developer 后台把能力勾上。
    func fetchDailyForecast(at coordinate: GeocodedCoordinate, date: Date) async throws -> DailyForecast? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let service = WeatherService.shared
        let weather = try await service.weather(for: location)
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        let dayWeather = weather.dailyForecast.forecast.filter { day in
            day.date >= start && day.date < end
        }
        return dayWeather.first.map(DailyForecast.init(dayWeather:))
    }
}

extension DailyForecast {
    init(dayWeather: DayWeather) {
        self.init(
            highCelsius: dayWeather.highTemperature.converted(to: .celsius).value,
            lowCelsius: dayWeather.lowTemperature.converted(to: .celsius).value,
            precipitationChance: dayWeather.precipitationChance,
            precipitationAmountMillimeters: dayWeather.precipitationAmount.converted(to: .millimeters).value,
            windSpeedKilometersPerHour: dayWeather.wind.speed.converted(to: .kilometersPerHour).value,
            condition: WeatherConditionKind(dayWeather: dayWeather.condition)
        )
    }
}

extension WeatherConditionKind {
    init(dayWeather: WeatherCondition) {
        switch dayWeather {
        case .clear, .mostlyClear, .partlyCloudy, .hot, .frigid:
            self = .clear
        case .cloudy, .mostlyCloudy:
            self = .cloudy
        case .rain, .drizzle, .freezingDrizzle, .freezingRain, .heavyRain, .sunShowers:
            self = .rain
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .hail:
            self = .snow
        case .sleet, .wintryMix:
            self = .sleet
        case .thunderstorms, .tropicalStorm, .hurricane,
             .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            self = .thunderstorm
        case .windy, .breezy:
            self = .wind
        case .foggy:
            self = .fog
        case .haze, .smoky, .blowingDust:
            self = .haze
        @unknown default:
            self = .unknown
        }
    }
}

final class CoreLocationGeocoding: Geocoding, @unchecked Sendable {
    private let cache: GeocodeCache
    private let geocoder: CLGeocoder

    init(cache: GeocodeCache = GeocodeCache(), geocoder: CLGeocoder = CLGeocoder()) {
        self.cache = cache
        self.geocoder = geocoder
    }

    func resolve(city: String?, address: String?) async throws -> GeocodedCoordinate? {
        if let cached = cache.coordinate(forCity: city, address: address) {
            return cached
        }
        let query = Self.composeQuery(city: city, address: address)
        guard !query.isEmpty else { return nil }
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let location = placemarks.first?.location else { return nil }
        let coord = GeocodedCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        cache.store(coord, city: city, address: address)
        return coord
    }

    private static func composeQuery(city: String?, address: String?) -> String {
        let parts = [city, address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
