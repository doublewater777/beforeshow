import Foundation

/// One enamel pin on the backstage-pass lanyard.
struct FootprintMilestone: Equatable, Identifiable {
    enum Kind: Equatable {
        case first
        case ordinal(Int)
        case firstAway(city: String)
        case peakYear(year: Int, count: Int)
        case latest(Int)
        case locked(target: Int, remaining: Int)
    }

    let kind: Kind
    /// The show the pin commemorates; locked pins have none.
    let showID: UUID?

    var id: String {
        switch kind {
        case .first: return "first"
        case let .ordinal(value): return "ordinal-\(value)"
        case .firstAway: return "away"
        case let .peakYear(year, _): return "peak-\(year)"
        case let .latest(value): return "latest-\(value)"
        case let .locked(target, _): return "locked-\(target)"
        }
    }

    var isLocked: Bool {
        if case .locked = kind { return true }
        return false
    }
}

@MainActor
enum FootprintMilestoneBuilder {
    static let ordinalTargets = [10, 25, 50, 100, 200, 500]

    /// `shows` must be the archived shows; order does not matter.
    static func make(shows: [Show]) -> [FootprintMilestone] {
        let ordered = FootprintArchiveRankingBuilder.chronological(shows)
        guard let first = ordered.first else { return [] }
        var pins = [FootprintMilestone(kind: .first, showID: first.id)]

        if let reached = ordinalTargets.last(where: { $0 <= ordered.count }), reached > 1 {
            pins.append(FootprintMilestone(kind: .ordinal(reached), showID: ordered[reached - 1].id))
        }
        if let away = firstAway(in: ordered) {
            pins.append(away)
        }
        if let peak = peakYear(in: ordered) {
            pins.append(peak)
        }
        let latestOrdinal = ordered.count
        if latestOrdinal > 1, !ordinalTargets.contains(latestOrdinal), let latest = ordered.last {
            pins.append(FootprintMilestone(kind: .latest(latestOrdinal), showID: latest.id))
        }
        if let target = ordinalTargets.first(where: { $0 > ordered.count }) {
            pins.append(FootprintMilestone(kind: .locked(target: target, remaining: target - ordered.count), showID: nil))
        }
        return pins
    }

    /// Home is the city with the most shows; the first show elsewhere earns the pin.
    private static func firstAway(in ordered: [Show]) -> FootprintMilestone? {
        let cities = ordered.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
        let counts = Dictionary(grouping: cities, by: { $0 }).mapValues(\.count)
        guard counts.count > 1,
              let home = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key,
              let show = ordered.first(where: {
                  guard let city = FootprintTextNormalizer.nonEmptyTrimmed($0.city) else { return false }
                  return city != home
              }),
              let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city) else { return nil }
        return FootprintMilestone(kind: .firstAway(city: city), showID: show.id)
    }

    /// Only meaningful once there is more than one year to compare; ties go to the earlier year.
    private static func peakYear(in ordered: [Show]) -> FootprintMilestone? {
        let byYear = Dictionary(grouping: ordered) {
            $0.timingCalendar().component(.year, from: $0.effectiveDate)
        }
        guard byYear.count > 1,
              let peak = byYear.max(by: {
                  $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count
              }) else { return nil }
        return FootprintMilestone(kind: .peakYear(year: peak.key, count: peak.value.count), showID: peak.value.first?.id)
    }
}
