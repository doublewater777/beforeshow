import Foundation
import MapKit
import SwiftData

struct FootprintYearSpan: Equatable, Hashable {
    let first: Int
    let latest: Int

    var isSingleYear: Bool { first == latest }
}

struct FootprintMonthActivity: Identifiable, Equatable, Hashable {
    let month: Int
    let showCount: Int
    let durationMinutes: Int

    var id: Int { month }
}

struct FootprintYearActivity: Identifiable, Equatable {
    let year: Int
    let months: [FootprintMonthActivity]

    var id: Int { year }
    var totalShows: Int { months.reduce(0) { $0 + $1.showCount } }

    var peakMonth: FootprintMonthActivity? {
        months
            .filter { $0.showCount > 0 }
            .sorted {
                $0.showCount == $1.showCount
                    ? $0.month < $1.month
                    : $0.showCount > $1.showCount
            }
            .first
    }

}

struct FootprintYearArchiveSummary: Equatable {
    let year: Int
    let showCount: Int
    let durationMinutes: Int
}

struct FootprintArtistArchiveItem: Identifiable, Equatable, Hashable {
    let name: String
    let count: Int
    let showIDs: [UUID]
    let yearSpan: FootprintYearSpan
    let artworkURL: URL?
    /// 已持久化的代表专辑封面;nil 时由视图层触发解析并写回 ArtistSlot。
    let albumArtworkURL: URL?

    var id: String { name }
    var firstShowID: UUID? { showIDs.first }
    var latestShowID: UUID? { showIDs.last }
    var rankItem: FootprintRankItem { FootprintRankItem(name: name, count: count) }
}

struct FootprintCityArchiveItem: Identifiable, Equatable, Hashable {
    let name: String
    let count: Int
    let venueCount: Int
    let showIDs: [UUID]
    let yearSpan: FootprintYearSpan

    var id: String { name }
    var firstShowID: UUID? { showIDs.first }
    var latestShowID: UUID? { showIDs.last }
    var rankItem: FootprintRankItem { FootprintRankItem(name: name, count: count) }
}

enum FootprintMapZoom {
    static let minimum: CGFloat = 1
    static let maximum: CGFloat = 1.7

    static func settledScale(current: CGFloat, gesture: CGFloat) -> CGFloat {
        min(max(current * gesture, minimum), maximum)
    }
}

struct FootprintVenueArchiveItem: Identifiable, Equatable, Hashable {
    let name: String
    let count: Int
    let cities: [String]
    let showIDs: [UUID]
    let yearSpan: FootprintYearSpan

    var id: String { name }
    var firstShowID: UUID? { showIDs.first }
    var latestShowID: UUID? { showIDs.last }
    var isRevisited: Bool { count > 1 }
    var rankItem: FootprintRankItem { FootprintRankItem(name: name, count: count) }
}

@MainActor
extension FootprintArchiveSnapshot {
    var artistArchiveItems: [FootprintArtistArchiveItem] {
        FootprintArchiveRankingBuilder.artists(in: shows)
    }

    var cityArchiveItems: [FootprintCityArchiveItem] {
        FootprintArchiveRankingBuilder.cities(in: shows)
    }

    var venueArchiveItems: [FootprintVenueArchiveItem] {
        FootprintArchiveRankingBuilder.venues(in: shows)
    }

    func yearActivity(for year: Int) -> FootprintYearActivity? {
        guard let group = years.first(where: { $0.year == year }) else { return nil }
        return FootprintYearActivity(
            year: year,
            months: FootprintArchiveRankingBuilder.months(in: group.shows)
        )
    }

    var allYearActivities: [FootprintYearActivity] {
        years.map { group in
            FootprintYearActivity(
                year: group.year,
                months: FootprintArchiveRankingBuilder.months(in: group.shows)
            )
        }
    }

    func yearArchiveSummary(for year: Int) -> FootprintYearArchiveSummary? {
        guard let group = years.first(where: { $0.year == year }),
              let activity = yearActivity(for: year) else { return nil }
        return FootprintYearArchiveSummary(
            year: year,
            showCount: group.shows.count,
            durationMinutes: activity.months.reduce(0) { $0 + $1.durationMinutes }
        )
    }

    func shows(for ids: [UUID]) -> [Show] {
        let byID = Dictionary(uniqueKeysWithValues: shows.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    static func identityOnly(shows: [Show]) -> FootprintArchiveSnapshot {
        FootprintArchiveSnapshot(
            shows: shows,
            artists: [],
            cities: [],
            venues: [],
            years: [],
            currentYearCount: 0,
            totalDurationMinutes: 0
        )
    }
}

@MainActor
enum FootprintArchiveRankingBuilder {
    static func artists(in shows: [Show]) -> [FootprintArtistArchiveItem] {
        var byName: [String: [Show]] = [:]
        for show in shows {
            for artist in Set(show.artistNames) {
                byName[artist, default: []].append(show)
            }
        }
        return byName.compactMap { name, related in
            makeArtist(name: name, shows: related)
        }.sorted(by: sortItems)
    }

    static func cities(in shows: [Show]) -> [FootprintCityArchiveItem] {
        let grouped = Dictionary(grouping: shows) { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
        return grouped.compactMap { name, related in
            guard let name else { return nil }
            let ordered = chronological(related)
            let venues = Set(related.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.venueName) })
            return FootprintCityArchiveItem(
                name: name,
                count: related.count,
                venueCount: venues.count,
                showIDs: ordered.map(\.id),
                yearSpan: span(for: ordered)
            )
        }.sorted(by: sortItems)
    }

    static func venues(in shows: [Show]) -> [FootprintVenueArchiveItem] {
        let grouped = Dictionary(grouping: shows) { FootprintTextNormalizer.nonEmptyTrimmed($0.venueName) }
        return grouped.compactMap { name, related in
            guard let name else { return nil }
            let ordered = chronological(related)
            let cities = Set(related.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) })
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return FootprintVenueArchiveItem(
                name: name,
                count: related.count,
                cities: cities,
                showIDs: ordered.map(\.id),
                yearSpan: span(for: ordered)
            )
        }.sorted(by: sortItems)
    }

    static func months(in shows: [Show]) -> [FootprintMonthActivity] {
        let totals = shows.reduce(into: [Int: (count: Int, duration: Int)]()) { result, show in
            let calendar = show.timingCalendar()
            let month = calendar.component(.month, from: show.effectiveDate)
            let state = CurrentShowTimeState(show: show, calendar: calendar)
            let duration = ShowDurationFormatter.minutes(for: show, timeState: state) ?? 0
            let current = result[month] ?? (count: 0, duration: 0)
            result[month] = (current.count + 1, current.duration + duration)
        }
        return (1...12).map { month in
            let value = totals[month] ?? (count: 0, duration: 0)
            return FootprintMonthActivity(
                month: month,
                showCount: value.count,
                durationMinutes: value.duration
            )
        }
    }

    private static func makeArtist(name: String, shows: [Show]) -> FootprintArtistArchiveItem? {
        let ordered = chronological(shows)
        guard !ordered.isEmpty else { return nil }
        let artworkURL = ordered.lazy
            .flatMap(\.artists)
            .first { FootprintTextNormalizer.nonEmptyTrimmed($0.name) == name }
            .flatMap { slot in
                slot.avatarURL
                    .flatMap(FootprintTextNormalizer.nonEmptyTrimmed)
                    .flatMap(URL.init(string:))
            }
        let albumArtworkURL = ordered.lazy
            .flatMap(\.artists)
            .first { FootprintTextNormalizer.nonEmptyTrimmed($0.name) == name }
            .flatMap { slot in
                slot.albumArtworkURL
                    .flatMap(FootprintTextNormalizer.nonEmptyTrimmed)
                    .flatMap(URL.init(string:))
            }
        return FootprintArtistArchiveItem(
            name: name,
            count: ordered.count,
            showIDs: ordered.map(\.id),
            yearSpan: span(for: ordered),
            artworkURL: artworkURL,
            albumArtworkURL: albumArtworkURL
        )
    }

    private static func sortItems(_ lhs: FootprintArtistArchiveItem, _ rhs: FootprintArtistArchiveItem) -> Bool {
        lhs.count == rhs.count
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.count > rhs.count
    }

    private static func sortItems(_ lhs: FootprintCityArchiveItem, _ rhs: FootprintCityArchiveItem) -> Bool {
        lhs.count == rhs.count
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.count > rhs.count
    }

    private static func sortItems(_ lhs: FootprintVenueArchiveItem, _ rhs: FootprintVenueArchiveItem) -> Bool {
        lhs.count == rhs.count
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.count > rhs.count
    }

    private static func span(for shows: [Show]) -> FootprintYearSpan {
        let ordered = chronological(shows)
        let first = ordered.first.map(year(for:)) ?? 0
        let latest = ordered.last.map(year(for:)) ?? first
        return FootprintYearSpan(first: first, latest: latest)
    }

    private static func year(for show: Show) -> Int {
        show.timingCalendar().component(.year, from: show.effectiveDate)
    }

    static func chronological(_ shows: [Show]) -> [Show] {
        shows.sorted {
            let lhs = effectiveStart(for: $0)
            let rhs = effectiveStart(for: $1)
            if lhs != rhs { return lhs < rhs }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func effectiveStart(for show: Show) -> Date {
        let calendar = show.timingCalendar()
        let day = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        let time = calendar.dateComponents([.hour, .minute, .second], from: show.startTime)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components) ?? show.effectiveDate
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
        for name in names where cache[name] == nil {
            if let coordinate = await resolve(name) {
                cache[name] = coordinate
                persist()
            }
        }
        return cache.filter { names.contains($0.key) }
    }

    /// Synchronous read of the in-memory cache — used to seed view state so
    /// offscreen export renders (no time for `.task`) still place city pins.
    func cachedCoordinates(for cityNames: [String]) -> [String: FootprintCityCoordinate] {
        let names = Set(cityNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed))
        return cache.filter { names.contains($0.key) }
    }

    private func resolve(_ name: String) async -> FootprintCityCoordinate? {
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

enum FootprintCoverBadge: String, Equatable {
    case memory = "MEMORY"
    case keepsake = "KEEPSAKE"
    case archive = "ARCHIVE"
}

enum FootprintCoverSource: Equatable {
    case local(URL)
    case remote(URL)
    case archive
}

struct FootprintCover: Identifiable, Equatable {
    let showID: UUID
    let source: FootprintCoverSource
    let badge: FootprintCoverBadge
    let ordinal: Int
    let variant: Int

    var id: UUID { showID }
}

enum FootprintArchiveCoverLayout {
    static func variant(for id: UUID) -> Int {
        let value = id.uuidString.utf8.reduce(UInt64(5381)) { hash, byte in
            (hash &* 33) &+ UInt64(byte)
        }
        return Int(value % 4)
    }
}

@MainActor
enum FootprintCoverResolver {
    static func resolve(
        shows: [Show],
        fragments: [MemoryFragment],
        assets: [ShowAsset]
    ) -> [UUID: FootprintCover] {
        let ordered = FootprintArchiveRankingBuilder.chronological(shows)
        let ordinals = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset + 1) })
        let fragmentsByShow = Dictionary(grouping: fragments, by: \.showID)
        let assetsByShow = Dictionary(grouping: assets, by: \.showID)

        return Dictionary(uniqueKeysWithValues: shows.map { show in
            let fragments = fragmentsByShow[show.id] ?? []
            let assets = assetsByShow[show.id] ?? []
            let cover = resolve(
                show: show,
                fragments: fragments,
                assets: assets,
                ordinal: ordinals[show.id] ?? 1
            )
            return (show.id, cover)
        })
    }

    private static func resolve(
        show: Show,
        fragments: [MemoryFragment],
        assets: [ShowAsset],
        ordinal: Int
    ) -> FootprintCover {
        let memoryItems = fragments
            .flatMap(\.orderedMediaItems)
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        if let memory = memoryItems.first(where: { $0.kind == .photo || $0.kind == .video }) {
            let path = memory.thumbnailRelativePath ?? memory.relativePath
            return FootprintCover(
                showID: show.id,
                source: .local(MemoryMediaLocation.applicationSupport().url(for: path)),
                badge: .memory,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        if let ticket = assets.first(where: { $0.kind == .ticket }),
           let location = try? ShowAssetMediaLocation.applicationSupport() {
            return FootprintCover(
                showID: show.id,
                source: .local(location.rootDirectory.appendingPathComponent(ticket.relativePath)),
                badge: .keepsake,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        if let posterPath = show.dynamicCover?.posterRelativePath,
           !posterPath.isEmpty,
           let location = try? DynamicCoverMediaLocation.applicationSupport() {
            return FootprintCover(
                showID: show.id,
                source: .local(location.url(for: posterPath)),
                badge: .archive,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        if let rawURL = show.coverImageURL,
           let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FootprintCover(
                showID: show.id,
                source: url.isFileURL ? .local(url) : .remote(url),
                badge: .archive,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        return FootprintCover(
            showID: show.id,
            source: .archive,
            badge: .archive,
            ordinal: ordinal,
            variant: FootprintArchiveCoverLayout.variant(for: show.id)
        )
    }
}

struct FootprintVisibility: Equatable {
    let showCount: Int
    let yearCount: Int
    let artistCount: Int
    let cityCount: Int
    let venueCount: Int
    let hasRevisitedVenue: Bool

    var isSeed: Bool { showCount == 1 }
    var showsTrend: Bool { showCount >= 5 }
    var showsYearComparison: Bool { yearCount >= 2 }
    var showsTopThree: Bool { showCount >= 3 }
}

@MainActor
extension FootprintArchiveSnapshot {
    var visibility: FootprintVisibility {
        FootprintVisibility(
            showCount: shows.count,
            yearCount: years.count,
            artistCount: artistArchiveItems.count,
            cityCount: cityArchiveItems.count,
            venueCount: venueArchiveItems.count,
            hasRevisitedVenue: venueArchiveItems.contains(where: \.isRevisited)
        )
    }
}
