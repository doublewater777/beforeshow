import Foundation

/// What the marquee at the Footprints entrance says this week.
struct FootprintMarqueeStatus: Equatable {
    let totalShows: Int
    /// Whole days since the latest archived show; nil before the first one.
    let daysSinceLast: Int?
    let nextShowID: UUID?
    let nextShowName: String?
    let nextShowCity: String?
    let nextMonth: Int?
    let nextDay: Int?
}

/// How a venue's neon sign burns: brightness from visits, steadiness from recency.
struct FootprintNeonSign: Equatable, Identifiable {
    enum Glow: Int, Comparable {
        case faint = 1, warm, full
        static func < (lhs: Glow, rhs: Glow) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Steadiness: Equatable {
        case steady
        case flickering
        case failing
    }

    let venue: FootprintVenueArchiveItem
    let glow: Glow
    let steadiness: Steadiness
    let daysSinceLast: Int

    var id: String { venue.id }
}

/// One line printed on the back of the tour shirt.
struct FootprintTourStop: Equatable, Identifiable {
    let city: String
    let count: Int
    let firstShowID: UUID?
    let firstMonth: Int
    let firstDay: Int
    let firstYear: Int
    let isNext: Bool

    var id: String { isNext ? "next|\(city)" : city }
}

@MainActor
enum FootprintStagePolicy {
    static let neonSignLimit = 6

    static func marquee(
        archived: [Show],
        allShows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FootprintMarqueeStatus {
        let latest = archived.max { $0.effectiveDate < $1.effectiveDate }
        let next = nextUpcoming(allShows, archived: archived, now: now)
        let nextParts = next.map {
            $0.timingCalendar(fallback: calendar).dateComponents([.month, .day], from: $0.effectiveDate)
        }
        return FootprintMarqueeStatus(
            totalShows: archived.count,
            daysSinceLast: latest.map { days(from: $0, to: now, calendar: calendar) },
            nextShowID: next?.id,
            nextShowName: next?.name,
            nextShowCity: next.flatMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) },
            nextMonth: nextParts?.month,
            nextDay: nextParts?.day
        )
    }

    /// Signs only for venues visited more than once; single visits stay dark.
    static func neonSigns(
        venues: [FootprintVenueArchiveItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FootprintNeonSign] {
        let lit = venues.filter(\.isRevisited).prefix(neonSignLimit)
        let top = lit.map(\.count).max() ?? 1
        return lit.map { venue in
            let days = max(0, calendar.dateComponents([.day], from: venue.latestShowDate, to: now).day ?? 0)
            return FootprintNeonSign(
                venue: venue,
                glow: glow(count: venue.count, top: top),
                steadiness: steadiness(daysSinceLast: days),
                daysSinceLast: days
            )
        }
    }

    static func steadiness(daysSinceLast days: Int) -> FootprintNeonSign.Steadiness {
        switch days {
        case ..<365: return .steady
        case ..<730: return .flickering
        default: return .failing
        }
    }

    static func glow(count: Int, top: Int) -> FootprintNeonSign.Glow {
        let ratio = Double(count) / Double(max(top, 1))
        if ratio >= 0.7 { return .full }
        if ratio >= 0.4 { return .warm }
        return .faint
    }

    /// Cities in the order they were first visited, with the next new city appended.
    static func tourStops(
        cities: [FootprintCityArchiveItem],
        archive: FootprintArchiveSnapshot,
        allShows: [Show],
        now: Date = Date()
    ) -> [FootprintTourStop] {
        var stops: [(stop: FootprintTourStop, first: Date)] = cities.compactMap { item in
            guard let firstID = item.firstShowID, let show = archive.shows(for: [firstID]).first else { return nil }
            let showCalendar = show.timingCalendar()
            let parts = showCalendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
            return (
                FootprintTourStop(
                    city: item.name,
                    count: item.count,
                    firstShowID: firstID,
                    firstMonth: parts.month ?? 1,
                    firstDay: parts.day ?? 1,
                    firstYear: parts.year ?? 0,
                    isNext: false
                ),
                show.effectiveDate
            )
        }
        stops.sort { $0.first < $1.first }
        var result = stops.map(\.stop)
        let visited = Set(cities.map(\.name))
        let archivedIDs = Set(archive.shows.map(\.id))
        let upcoming = allShows
            .filter { isDated($0) && $0.effectiveDate >= now && !archivedIDs.contains($0.id) }
            .sorted { $0.effectiveDate < $1.effectiveDate }
        if let next = upcoming.first(where: {
            guard let city = FootprintTextNormalizer.nonEmptyTrimmed($0.city) else { return false }
            return !visited.contains(city)
        }), let city = FootprintTextNormalizer.nonEmptyTrimmed(next.city) {
            let parts = next.timingCalendar().dateComponents([.year, .month, .day], from: next.effectiveDate)
            result.append(FootprintTourStop(
                city: city,
                count: 0,
                firstShowID: next.id,
                firstMonth: parts.month ?? 1,
                firstDay: parts.day ?? 1,
                firstYear: parts.year ?? 0,
                isNext: true
            ))
        }
        return result
    }

    /// For each artist on this bill: how many times you had seen them by this night (this one included).
    static func reunions(for show: Show, in archived: [Show]) -> [(name: String, nth: Int)] {
        let ordered = FootprintArchiveRankingBuilder.chronological(archived)
        let upTo = ordered.prefix { $0.id != show.id } + [show]
        var seen = Set<String>()
        return show.artistNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed).filter { seen.insert($0).inserted }.map { name in
            (name, upTo.filter { $0.artistNames.contains(name) }.count)
        }
    }

    static func nextUpcoming(_ shows: [Show], archived: [Show], now: Date) -> Show? {
        let archivedIDs = Set(archived.map(\.id))
        return shows
            .filter { isDated($0) && !archivedIDs.contains($0.id) && $0.effectiveDate >= now }
            .min { $0.effectiveDate < $1.effectiveDate }
    }

    /// Still going ahead on a known date: not cancelled, and not postponed with no new date,
    /// which is not a date anyone can count down to (see ADR 0030).
    static func isDated(_ show: Show) -> Bool {
        show.changeStatus != .canceled && !(show.changeStatus == .postponed && show.postponedDate == nil)
    }

    /// Counted from the show's last day, so a festival that just ended was 1 day ago, not 3.
    private static func days(from show: Show, to now: Date, calendar: Calendar) -> Int {
        let showCalendar = show.timingCalendar(fallback: calendar)
        let lastDay = CurrentShowTimeState.effectiveEndDate(timing: show.timingFields, calendar: showCalendar) ?? show.effectiveDate
        let start = showCalendar.startOfDay(for: max(show.effectiveDate, lastDay))
        let end = showCalendar.startOfDay(for: now)
        return max(0, showCalendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }
}
