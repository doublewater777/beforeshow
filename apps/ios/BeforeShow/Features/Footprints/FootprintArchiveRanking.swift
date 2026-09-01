import Foundation

struct FootprintYearSpan: Equatable, Hashable {
    let first: Int
    let latest: Int

    var isSingleYear: Bool { first == latest }

    /// 展示用年份跨度文案(单年只显示一年)。
    var displayText: String {
        isSingleYear ? String(first) : BSLocalization.format("%lld–%lld", first, latest)
    }
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
    let latestShowDate: Date
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

struct FootprintVenueArchiveItem: Identifiable, Equatable, Hashable {
    let name: String
    let count: Int
    let cities: [String]
    let showIDs: [UUID]
    let latestShowDate: Date
    let yearSpan: FootprintYearSpan

    var id: String {
        let city = cities.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ",")
        return city.isEmpty ? name : "\(city)|\(name)"
    }
    var firstShowID: UUID? { showIDs.first }
    var latestShowID: UUID? { showIDs.last }
    var isRevisited: Bool { count > 1 }
    var rankItem: FootprintRankItem { FootprintRankItem(name: name, count: count, id: id) }
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

    /// 年度高光场:优先回忆/纪念徽章场,否则取当年第一场。
    func yearHighlightShow(for year: Int, covers: [UUID: FootprintCover]) -> Show? {
        guard let shows = years.first(where: { $0.year == year })?.shows else { return nil }
        return shows.first(where: { covers[$0.id]?.badge == .memory })
            ?? shows.first(where: { covers[$0.id]?.badge == .keepsake })
            ?? shows.first
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
    private struct CacheRevision: Equatable {
        let id: UUID
        let updatedAt: Date
        let city: String?
        let venueName: String?
        let artistNames: [String]
        let artistMedia: [String]
    }

    private struct RankingCache {
        let revisions: [CacheRevision]
        var artists: [FootprintArtistArchiveItem]?
        var cities: [FootprintCityArchiveItem]?
        var venues: [FootprintVenueArchiveItem]?
    }

    private static var rankingCache: RankingCache?

    static func artists(in shows: [Show]) -> [FootprintArtistArchiveItem] {
        prepareCache(for: shows)
        if let cached = rankingCache?.artists { return cached }

        var byName: [String: [Show]] = [:]
        for show in shows {
            for artist in Set(show.artistNames) {
                byName[artist, default: []].append(show)
            }
        }
        let result = byName.compactMap { name, related in
            makeArtist(name: name, shows: related)
        }.sorted(by: sortItems)
        rankingCache?.artists = result
        return result
    }

    static func cities(in shows: [Show]) -> [FootprintCityArchiveItem] {
        prepareCache(for: shows)
        if let cached = rankingCache?.cities { return cached }

        let grouped = Dictionary(grouping: shows) { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
        let result = grouped.compactMap { name, related in
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
        rankingCache?.cities = result
        return result
    }

    static func venues(in shows: [Show]) -> [FootprintVenueArchiveItem] {
        prepareCache(for: shows)
        if let cached = rankingCache?.venues { return cached }

        let grouped = Dictionary(grouping: shows) { venueIdentityKey(for: $0) }
        let result = grouped.compactMap { key, related in
            guard let key else { return nil }
            let ordered = chronological(related)
            let cities = Set(related.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) })
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return FootprintVenueArchiveItem(
                name: key.venue,
                count: related.count,
                cities: cities,
                showIDs: ordered.map(\.id),
                latestShowDate: ordered.last.map(effectiveStart(for:)) ?? .distantPast,
                yearSpan: span(for: ordered)
            )
        }.sorted(by: sortItems)
        rankingCache?.venues = result
        return result
    }

    private static func prepareCache(for shows: [Show]) {
        let revisions = shows.map { show in
            CacheRevision(
                id: show.id,
                updatedAt: show.updatedAt,
                city: show.city,
                venueName: show.venueName,
                artistNames: show.artistNames,
                artistMedia: show.artists.map { artist in
                    [artist.name, artist.avatarURL ?? "", artist.albumArtworkURL ?? ""]
                        .joined(separator: "\u{1F}")
                }
            )
        }
        if rankingCache?.revisions != revisions {
            rankingCache = RankingCache(
                revisions: revisions,
                artists: nil,
                cities: nil,
                venues: nil
            )
        }
    }

    private struct VenueIdentityKey: Hashable {
        let city: String
        let venue: String
    }

    private static func venueIdentityKey(for show: Show) -> VenueIdentityKey? {
        guard let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) else { return nil }
        return VenueIdentityKey(city: FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? "", venue: venue)
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
        let matchingSlots = ordered.lazy
            .flatMap(\.artists)
            .filter { FootprintTextNormalizer.nonEmptyTrimmed($0.name) == name }
        let artworkURL = matchingSlots
            .compactMap { slot in
                slot.avatarURL
                    .flatMap(FootprintTextNormalizer.nonEmptyTrimmed)
                    .flatMap(URL.init(string:))
            }
            .first
        let albumArtworkURL = matchingSlots
            .compactMap { slot in
                slot.albumArtworkURL
                    .flatMap(FootprintTextNormalizer.nonEmptyTrimmed)
                    .flatMap(URL.init(string:))
            }
            .first
        return FootprintArtistArchiveItem(
            name: name,
            count: ordered.count,
            showIDs: ordered.map(\.id),
            latestShowDate: ordered.last.map(effectiveStart(for:)) ?? .distantPast,
            yearSpan: span(for: ordered),
            artworkURL: artworkURL,
            albumArtworkURL: albumArtworkURL
        )
    }

    private static func sortItems(_ lhs: FootprintArtistArchiveItem, _ rhs: FootprintArtistArchiveItem) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        if lhs.latestShowDate != rhs.latestShowDate { return lhs.latestShowDate > rhs.latestShowDate }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func sortItems(_ lhs: FootprintCityArchiveItem, _ rhs: FootprintCityArchiveItem) -> Bool {
        lhs.count == rhs.count
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.count > rhs.count
    }

    private static func sortItems(_ lhs: FootprintVenueArchiveItem, _ rhs: FootprintVenueArchiveItem) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        if lhs.latestShowDate != rhs.latestShowDate { return lhs.latestShowDate > rhs.latestShowDate }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
