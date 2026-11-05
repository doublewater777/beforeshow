import CoreLocation
import MapKit

/// One place on the map: every show you saw at the same venue.
struct FootprintVenueSpot: Equatable, Identifiable {
    let id: String
    let venue: String?
    let city: String?
    /// Newest first; the first poster stands for the spot.
    let showIDs: [UUID]
    let firstDate: Date
    /// What to look the venue up by, best first: its address, venue with city, venue alone.
    let queries: [String]
}

/// Spots close enough at the current zoom to share one pin.
struct FootprintMapCluster: Equatable, Identifiable {
    let spots: [FootprintVenueSpot]
    let latitude: Double
    let longitude: Double

    var id: String { spots.map(\.id).joined(separator: "+") }
    var showCount: Int { spots.reduce(0) { $0 + $1.showIDs.count } }
    /// The spot with the most nights leads, so its poster shows.
    var lead: FootprintVenueSpot { spots[0] }
}

enum FootprintVenueMapPolicy {
    static func spots(from shows: [Show]) -> [FootprintVenueSpot] {
        let grouped = Dictionary(grouping: shows) { key(venue: $0.venueName, city: $0.city) }
        return grouped.map { key, shows in
            let ordered = shows.sorted { $0.effectiveDate > $1.effectiveDate }
            let sample = ordered[0]
            let venue = FootprintTextNormalizer.nonEmptyTrimmed(sample.venueName)
            let city = FootprintTextNormalizer.nonEmptyTrimmed(sample.city)
            let address = ordered.lazy.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.venueAddress) }.first
            let candidates = [address, venue.map { [city, $0].compactMap { $0 }.joined(separator: " ") }, venue].compactMap { $0 }
            let queries = candidates.enumerated().filter { !candidates.prefix($0.offset).contains($0.element) }.map(\.element)
            return FootprintVenueSpot(
                id: key,
                venue: venue,
                city: city,
                showIDs: ordered.map(\.id),
                firstDate: ordered.last?.effectiveDate ?? sample.effectiveDate,
                queries: queries
            )
        }
        .sorted { $0.firstDate < $1.firstDate }
    }

    /// Greedy grid merge: busier spots claim their neighbourhood first.
    /// `cell` is in degrees, about a tenth of the visible span.
    static func clusters(
        _ placed: [(spot: FootprintVenueSpot, latitude: Double, longitude: Double)],
        cell: Double
    ) -> [FootprintMapCluster] {
        var clusters: [(spots: [FootprintVenueSpot], latitude: Double, longitude: Double)] = []
        let ordered = placed.sorted { ($0.spot.showIDs.count, $1.spot.firstDate) > ($1.spot.showIDs.count, $0.spot.firstDate) }
        for item in ordered {
            if let index = clusters.firstIndex(where: { abs($0.latitude - item.latitude) < cell && abs($0.longitude - item.longitude) < cell }) {
                clusters[index].spots.append(item.spot)
            } else {
                clusters.append(([item.spot], item.latitude, item.longitude))
            }
        }
        return clusters.map { FootprintMapCluster(spots: $0.spots, latitude: $0.latitude, longitude: $0.longitude) }
    }

    private static func key(venue: String?, city: String?) -> String {
        let venueKey = FootprintTextNormalizer.nonEmptyTrimmed(venue)?.lowercased() ?? ""
        let cityKey = FootprintTextNormalizer.nonEmptyTrimmed(city)?.lowercased() ?? ""
        return venueKey.isEmpty ? "city|\(cityKey)" : "\(cityKey)|\(venueKey)"
    }
}

/// Finds where a venue is with Apple's local search, near its city, and remembers it.
@MainActor
final class FootprintVenueLocator {
    static let shared = FootprintVenueLocator()

    /// A match further than this from the city is a different place with the same name.
    private nonisolated static let maximumDistanceFromCity: CLLocationDistance = 80_000
    /// A match this close to the city centre is the city itself, not the venue.
    private nonisolated static let minimumDistanceFromCity: CLLocationDistance = 300
    private static let lookupsPerVisit = 40

    /// Keyed by what was searched for, so a corrected address is looked up again.
    private let cacheKey = "FootprintVenueLocator.cache.v3"
    private var cache: [String: FootprintCityCoordinate]
    /// Searches that found nothing this launch; skipped so the venues after them get their turn.
    private var misses: Set<String> = []

    private init(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "FootprintVenueLocator.cache.v2")
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: FootprintCityCoordinate].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Spot id → where it is. Spots it cannot place are left out; callers fall back to the city.
    func coordinates(for spots: [FootprintVenueSpot], cities: [String: FootprintCityCoordinate]) async -> [String: FootprintCityCoordinate] {
        let missing = spots.filter {
            let key = Self.lookupKey($0)
            return cache[key] == nil && !misses.contains(key) && !$0.queries.isEmpty
        }.prefix(Self.lookupsPerVisit)
        let found = await withTaskGroup(of: (String, FootprintCityCoordinate?).self) { group in
            for spot in missing {
                let near = spot.city.flatMap { cities[$0] }
                let key = Self.lookupKey(spot)
                group.addTask {
                    for query in spot.queries {
                        if let hit = await Self.resolve(query, near: near) { return (key, hit) }
                    }
                    return (key, nil)
                }
            }
            var collected: [String: FootprintCityCoordinate] = [:]
            for await (key, coordinate) in group {
                if let coordinate { collected[key] = coordinate } else { misses.insert(key) }
            }
            return collected
        }
        if !found.isEmpty {
            cache.merge(found) { _, new in new }
            if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: cacheKey) }
        }
        return spots.reduce(into: [:]) { result, spot in result[spot.id] = cache[Self.lookupKey(spot)] }
    }

    private static func lookupKey(_ spot: FootprintVenueSpot) -> String {
        ([spot.id] + spot.queries).joined(separator: "\u{1F}")
    }

    private nonisolated static func resolve(_ query: String, near: FootprintCityCoordinate?) async -> FootprintCityCoordinate? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let near {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.bsCoordinate
        if let near {
            let distance = CLLocation(latitude: near.latitude, longitude: near.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= maximumDistanceFromCity, distance >= minimumDistanceFromCity else { return nil }
        }
        return FootprintCityCoordinate(name: query, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
