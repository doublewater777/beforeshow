import Foundation
import MapKit

enum FootprintMapZoom {
    static let minimum: CGFloat = 1
    static let maximum: CGFloat = 1.7

    static func settledScale(current: CGFloat, gesture: CGFloat) -> CGFloat {
        min(max(current * gesture, minimum), maximum)
    }
}

struct FootprintCityCoordinate: Codable, Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct FootprintProjectedCoordinate: Equatable, Sendable {
    let x: Double
    let y: Double
}

enum FootprintCoordinateProjector {
    static func project(_ coordinates: [FootprintCityCoordinate]) -> [String: FootprintProjectedCoordinate] {
        guard !coordinates.isEmpty else { return [:] }
        let minLatitude = coordinates.map(\.latitude).min() ?? 0
        let maxLatitude = coordinates.map(\.latitude).max() ?? 0
        let minLongitude = coordinates.map(\.longitude).min() ?? 0
        let maxLongitude = coordinates.map(\.longitude).max() ?? 0
        let latitudeRange = maxLatitude - minLatitude
        let longitudeRange = maxLongitude - minLongitude
        let padding = 0.12
        let usable = 1 - padding * 2

        return Dictionary(uniqueKeysWithValues: coordinates.map { coordinate in
            let x = longitudeRange == 0
                ? 0.5
                : padding + ((coordinate.longitude - minLongitude) / longitudeRange) * usable
            let y = latitudeRange == 0
                ? 0.5
                : padding + ((maxLatitude - coordinate.latitude) / latitudeRange) * usable
            return (coordinate.name, FootprintProjectedCoordinate(x: x, y: y))
        })
    }
}

@MainActor
final class FootprintCityCoordinateResolver {
    static let shared = FootprintCityCoordinateResolver()

    private let cacheKey = "FootprintCityCoordinateResolver.cache.v1"
    private var cache: [String: FootprintCityCoordinate]

    private init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: FootprintCityCoordinate].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    func coordinates(for cityNames: [String]) async -> [String: FootprintCityCoordinate] {
        let names = Array(Set(cityNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed))).sorted()
        let missing = names.filter { cache[$0] == nil }
        guard !missing.isEmpty else {
            return cache.filter { names.contains($0.key) }
        }

        // Resolve each missing city in parallel. `resolve(_:)` is nonisolated
        // so its `MKLocalSearch` await does not serialize on the main actor.
        // The group collector re-enters `@MainActor` to write results into
        // `cache`, keeping the dictionary single-writer.
        let resolved = await withTaskGroup(
            of: (String, FootprintCityCoordinate?).self
        ) { group in
            for name in missing {
                group.addTask {
                    let coordinate = await self.resolve(name)
                    return (name, coordinate)
                }
            }
            var collected: [String: FootprintCityCoordinate] = [:]
            for await (name, coordinate) in group {
                if let coordinate {
                    self.cache[name] = coordinate
                    collected[name] = coordinate
                }
            }
            return collected
        }
        if !resolved.isEmpty {
            persist()
        }
        return cache.filter { names.contains($0.key) }
    }

    /// Synchronous read of the in-memory cache — used to seed view state so
    /// offscreen export renders (no time for `.task`) still place city pins.
    func cachedCoordinates(for cityNames: [String]) -> [String: FootprintCityCoordinate] {
        let names = Set(cityNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed))
        return cache.filter { names.contains($0.key) }
    }

    /// `nonisolated` so parallel `withTaskGroup` children can run their
    /// `MKLocalSearch` await off the main actor. The class owns the
    /// single-writer cache; this method must not touch `self.cache`.
    private nonisolated func resolve(_ name: String) async -> FootprintCityCoordinate? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else { return nil }
            let coordinate = mapItem.placemark.coordinate
            return FootprintCityCoordinate(
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            return nil
        }
    }

    private func persist(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
