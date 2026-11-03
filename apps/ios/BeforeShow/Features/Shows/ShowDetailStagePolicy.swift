import Foundation

/// Where a show stands, as the stage on its detail page shows it.
enum ShowStageMood: Equatable {
    case before(daysToGo: Int)
    case live
    case ended
    /// Postponed with no new date yet.
    case postponed
    case canceled
}

enum ShowDetailStagePolicy {
    static func mood(
        changeStatus: ShowChangeStatus,
        postponedDate: Date?,
        phase: HomeShowPhase,
        dayDistance: Int
    ) -> ShowStageMood {
        switch changeStatus {
        case .canceled:
            return .canceled
        case .postponed where postponedDate == nil:
            return .postponed
        case .postponed, .scheduled:
            switch phase {
            case .live: return .live
            case .ended: return .ended
            case .pre, .inactive: return .before(daysToGo: max(0, dayDistance))
            }
        }
    }

    /// Lamps on the truss already warm before doors: one far out, two the day before, all four on the day.
    static func warmLamps(daysToGo: Int) -> Int {
        switch daysToGo {
        case ...0: 4
        case 1: 2
        default: 1
        }
    }

    /// The backstage clock on the stage lip. `exact` shows the wall-clock time instead of the count.
    static func clock(
        for mood: ShowStageMood,
        start: Date?,
        end: Date?,
        now: Date,
        exact: Bool,
        calendar: Calendar
    ) -> (value: String, unit: String) {
        switch mood {
        case let .before(daysToGo):
            if exact, let start {
                return (format(start, "HH:mm", calendar), format(start, "EEE MM.dd", calendar))
            }
            if daysToGo > 0 {
                return (String(format: "D-%02d", daysToGo), "DAYS")
            }
            guard let start else { return ("D-00", "TODAY") }
            return (duration(from: now, to: start), "TO GO")
        case .live:
            guard let start else { return ("LIVE", "ON AIR") }
            return exact ? (format(start, "HH:mm", calendar), "START") : (duration(from: start, to: now), "ON AIR")
        case .ended:
            if exact, let end {
                return (format(end, "HH:mm", calendar), format(end, "EEE MM.dd", calendar))
            }
            return ("END", "HOUSE LIGHTS")
        case .postponed:
            return ("--:--", "TBD")
        case .canceled:
            return ("00:00", "OFF")
        }
    }

    /// For each artist on this bill: the how-manieth time this night makes, counting shows already attended.
    static func reunions(for show: Show, among shows: [Show], now: Date) -> [(name: String, nth: Int)] {
        let cutoff = min(show.effectiveDate, now)
        let attended = shows.filter { $0.id != show.id && $0.changeStatus != .canceled && $0.effectiveDate < cutoff }
        var seen = Set<String>()
        return show.artistNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { name in (name, attended.filter { $0.artistNames.contains(name) }.count + 1) }
    }

    private static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date).uppercased()
    }
}
