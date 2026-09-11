import Foundation
import CoreLocation

struct GeocodedCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

protocol Geocoding: Sendable {
    func resolve(city: String?, address: String?) async throws -> GeocodedCoordinate?
}

final class GeocodeCache: @unchecked Sendable {
    private static let ttl: TimeInterval = 24 * 60 * 60
    private static let keyPrefix = "mapGeocode."
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
