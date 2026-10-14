import Foundation

enum ShowChangeStatus: String, CaseIterable, Codable, Equatable {
    case scheduled
    case postponed
    case canceled
}

struct ShowSessionTiming: Equatable, Codable {
    var date: Date
    var startsAt: Date
    var endsAt: Date
}

/// App 与 Widget 共用的生命周期时间输入。
struct ShowTimingFields: Equatable, Codable {
    var date: Date
    var startTime: Date
    var endDate: Date?
    var endTime: Date?
    /// Fixed UTC offset reported by an external event page, when available.
    /// The Date values remain absolute instants; this offset preserves the
    /// venue-local calendar and clock when timing is displayed or recomputed.
    var timeZoneSecondsFromGMT: Int? = nil
    /// The end instant may carry a different fixed offset across a DST boundary.
    var endTimeZoneSecondsFromGMT: Int? = nil
    /// IANA timezone identifiers preserve DST rules when the source provides them.
    var timeZoneIdentifier: String? = nil
    var endTimeZoneIdentifier: String? = nil
    var sessions: [ShowSessionTiming]? = nil
    var sessionTimeZoneIdentifier: String? = nil
    var endedAt: Date? = nil
    var postponedDate: Date?
    var changeStatus: ShowChangeStatus

    var effectiveDate: Date {
        postponedDate ?? date
    }

    func eventCalendar(fallback: Calendar) -> Calendar {
        if let identifier = sessionTimeZoneIdentifier ?? timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            var calendar = fallback
            calendar.timeZone = timeZone
            return calendar
        }
        guard let timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: timeZoneSecondsFromGMT) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }

    /// Timetable days define actual sessions, including skipped dates. Preserve
    /// an earlier opening and a later explicit closing without truncating sets.
    func resolvedSessions(calendar: Calendar) -> [ShowSessionTiming] {
        var ranges = (sessions ?? []).filter { $0.startsAt < $0.endsAt }
            .sorted { $0.startsAt < $1.startsAt }
        guard !ranges.isEmpty else { return [] }
        let opening = CurrentShowTimeState.effectiveStartTime(timing: self, calendar: calendar)
        if calendar.isDate(opening, inSameDayAs: ranges[0].date) {
            ranges[0].startsAt = min(opening, ranges[0].startsAt)
        }
        if endTime != nil {
            let final = ranges.count - 1
            let closing = CurrentShowTimeState.dailyEndTime(on: ranges[final].date, timing: self, calendar: calendar)
            ranges[final].endsAt = max(closing, ranges[final].endsAt)
        }
        return ranges
    }

    func endEventCalendar(fallback: Calendar) -> Calendar {
        if let timeZoneIdentifier = endTimeZoneIdentifier ?? sessionTimeZoneIdentifier ?? timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            var calendar = fallback
            calendar.timeZone = timeZone
            return calendar
        }
        guard let offset = endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: offset) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }
}

enum ShowDateSelectionPolicy {
    static func normalizedDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
}
