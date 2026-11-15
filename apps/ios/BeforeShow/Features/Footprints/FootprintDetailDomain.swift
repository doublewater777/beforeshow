import Foundation

struct FootprintCompanionIdentity: Equatable {
    let name: String
    let ordinal: Int
}

struct FootprintDetailIdentity: Equatable {
    let showOrdinal: Int
    let cityOrdinal: Int?
    let companions: [FootprintCompanionIdentity]

    var companionName: String? {
        if companions.count == 1 { return companions[0].name }
        return CompanionNameList.joined(companions.map(\.name))
    }

    var companionOrdinal: Int? {
        companions.count == 1 ? companions[0].ordinal : nil
    }
}

@MainActor
enum FootprintDetailIdentityBuilder {
    static func make(
        show: Show,
        archive: FootprintArchiveSnapshot,
        calendar: Calendar = .current
    ) -> FootprintDetailIdentity {
        let orderedShows = archive.shows.sorted {
            compare($0, $1, calendar: calendar)
        }
        let showOrdinal = orderedShows.firstIndex { $0.id == show.id }.map { $0 + 1 } ?? 1

        let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city)
        let cityShows = city.map { city in
            orderedShows.filter { FootprintTextNormalizer.nonEmptyTrimmed($0.city) == city }
        } ?? []
        let cityOrdinal = cityShows.firstIndex { $0.id == show.id }.map { $0 + 1 }

        // Archive shows are already footprints, so this is `CompanionHistory`'s rule.
        let companions = show.companionNames.compactMap { name -> FootprintCompanionIdentity? in
            let companionShows = orderedShows.filter { $0.companionNames.contains(name) }
            guard let index = companionShows.firstIndex(where: { $0.id == show.id }) else {
                return nil
            }
            return FootprintCompanionIdentity(name: name, ordinal: index + 1)
        }

        return FootprintDetailIdentity(
            showOrdinal: showOrdinal,
            cityOrdinal: cityOrdinal,
            companions: companions
        )
    }

    private static func compare(_ lhs: Show, _ rhs: Show, calendar: Calendar) -> Bool {
        let lhsStart = effectiveStart(for: lhs, calendar: calendar)
        let rhsStart = effectiveStart(for: rhs, calendar: calendar)
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func effectiveStart(for show: Show, calendar: Calendar) -> Date {
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

enum FootprintTextNormalizer {
    static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum FootprintAccessibilityPolicy {
    static func memoryLabel(
        ordinal: Int,
        kind: String,
        recordedAt: Date,
        text: String? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        let kindAndTime = BSLocalization.format("第 %lld 条，%@，%@", ordinal, kind, BSDateFormat.clock(recordedAt, timeZone: timeZone))
        if let summary = summary(from: text) {
            return BSLocalization.format("打开记忆碎片，%@，内容：%@", kindAndTime, summary)
        }
        return BSLocalization.format("打开记忆碎片，%@", kindAndTime)
    }

    private static func summary(from text: String?) -> String? {
        guard let text = FootprintTextNormalizer.nonEmptyTrimmed(text) else { return nil }
        let summary = String(text.prefix(24))
        return summary.count < text.count ? "\(summary)…" : summary
    }
}

enum FootprintExportContentPolicy {
    static let timelineShowLimit = 12
    static let yearShowLimit = 12

    static func prefix<T>(_ items: [T], limit: Int) -> [T] {
        Array(items.prefix(limit))
    }

    static func remainingCount(total: Int, limit: Int) -> Int {
        max(0, total - limit)
    }

    static func remainingText(total: Int, limit: Int) -> String? {
        let remaining = remainingCount(total: total, limit: limit)
        guard remaining > 0 else { return nil }
        return BSLocalization.format("还有 %lld 场现场", Int64(remaining))
    }

    static func cappedYearGroups(_ years: [FootprintYearGroup], limit: Int) -> [FootprintYearGroup] {
        var remaining = limit
        var result: [FootprintYearGroup] = []
        for group in years {
            guard remaining > 0 else { break }
            let shows = Array(group.shows.prefix(remaining))
            remaining -= shows.count
            result.append(FootprintYearGroup(year: group.year, shows: shows))
        }
        return result
    }
}
