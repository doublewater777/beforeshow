import Foundation

enum TimetablePeriodFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case now
    case upNext
    case evening
    case interested

    var id: String { rawValue }
}

enum TimetableDayPart: String, CaseIterable, Sendable, Comparable {
    case morning
    case afternoon
    case evening

    static func < (lhs: TimetableDayPart, rhs: TimetableDayPart) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

enum TimetablePeriodPolicy {
    /// Determines whether a performance is currently on stage at reference date.
    static func isNow(startsAt: Date, endsAt: Date, at date: Date) -> Bool {
        startsAt <= date && date < endsAt
    }

    /// Determines whether a performance starts in the near future (within the upcoming window)
    /// relative to reference date. Default window is 2 hours (7200 seconds).
    static func isUpNext(
        startsAt: Date,
        at date: Date,
        window: TimeInterval = 7200
    ) -> Bool {
        date <= startsAt && startsAt <= date.addingTimeInterval(window)
    }

    /// Determines whether a performance is part of the evening schedule (18:00 or later)
    /// in the target timetable time zone.
    static func isEvening(startsAt: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: startsAt)
        return hour >= 18
    }

    /// Classifies the general time of day (morning, afternoon, evening) in the timetable time zone.
    static func dayPart(for startsAt: Date, timeZone: TimeZone) -> TimetableDayPart {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: startsAt)
        if hour < 12 {
            return .morning
        } else if hour < 18 {
            return .afternoon
        } else {
            return .evening
        }
    }

    /// Filters performances based on the user's selected period filter.
    static func matches(
        startsAt: Date,
        endsAt: Date,
        isInterested: Bool,
        filter: TimetablePeriodFilter,
        timeZone: TimeZone,
        referenceDate: Date = Date()
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .now:
            return isNow(startsAt: startsAt, endsAt: endsAt, at: referenceDate)
        case .upNext:
            return isUpNext(startsAt: startsAt, at: referenceDate)
        case .evening:
            return isEvening(startsAt: startsAt, timeZone: timeZone)
        case .interested:
            return isInterested
        }
    }
}
