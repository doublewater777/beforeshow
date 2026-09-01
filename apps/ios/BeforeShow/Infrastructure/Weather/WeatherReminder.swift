import Foundation
import CoreLocation

struct DailyForecast: Equatable, Sendable {
    let highCelsius: Double?
    let lowCelsius: Double?
    let precipitationChance: Double
    let precipitationAmountMillimeters: Double
    let windSpeedKilometersPerHour: Double
    let condition: WeatherConditionKind

    static let unavailable = DailyForecast(
        highCelsius: nil,
        lowCelsius: nil,
        precipitationChance: 0,
        precipitationAmountMillimeters: 0,
        windSpeedKilometersPerHour: 0,
        condition: .unknown
    )
}

enum WeatherConditionKind: String, Sendable {
    case clear
    case cloudy
    case rain
    case snow
    case sleet
    case thunderstorm
    case wind
    case fog
    case haze
    case unknown
}

extension WeatherConditionKind {
    var isWet: Bool {
        switch self {
        case .rain, .thunderstorm, .snow, .sleet:
            return true
        default:
            return false
        }
    }
}

struct GeocodedCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

protocol Geocoding: Sendable {
    func resolve(city: String?, address: String?) async throws -> GeocodedCoordinate?
}

final class GeocodeCache: @unchecked Sendable {
    private static let ttl: TimeInterval = 24 * 60 * 60
    private static let keyPrefix = "weatherGeocode."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func coordinate(forCity city: String?, address: String?) -> GeocodedCoordinate? {
        guard let key = Self.cacheKey(city: city, address: address) else { return nil }
        guard let payload = defaults.dictionary(forKey: key),
              let lat = payload["lat"] as? Double,
              let lon = payload["lon"] as? Double,
              let stored = payload["storedAt"] as? Double else {
            return nil
        }
        let storedAt = Date(timeIntervalSince1970: stored)
        guard Date().timeIntervalSince(storedAt) < Self.ttl else { return nil }
        return GeocodedCoordinate(latitude: lat, longitude: lon)
    }

    func store(_ coordinate: GeocodedCoordinate, city: String?, address: String?) {
        guard let key = Self.cacheKey(city: city, address: address) else { return }
        defaults.set(
            [
                "lat": coordinate.latitude,
                "lon": coordinate.longitude,
                "storedAt": Date().timeIntervalSince1970
            ],
            forKey: key
        )
    }

    private static func cacheKey(city: String?, address: String?) -> String? {
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedCity.isEmpty && trimmedAddress.isEmpty { return nil }
        return keyPrefix + "\(trimmedCity)|\(trimmedAddress)"
    }
}

protocol WeatherForecastProvider: Sendable {
    func fetchDailyForecast(at coordinate: GeocodedCoordinate, date: Date) async throws -> DailyForecast?
}

final class WeatherReminderDeduper: @unchecked Sendable {
    private static let keyPrefix = "weatherReminder."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasPostedToday(showID: UUID, day: Date, calendar: Calendar) -> Bool {
        defaults.bool(forKey: key(showID: showID, day: day, calendar: calendar))
    }

    func markPostedToday(showID: UUID, day: Date, calendar: Calendar) {
        defaults.set(true, forKey: key(showID: showID, day: day, calendar: calendar))
    }

    private func key(showID: UUID, day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return "\(Self.keyPrefix)\(showID.uuidString).\(stamp)"
    }
}
