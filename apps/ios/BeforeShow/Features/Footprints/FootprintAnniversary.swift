import Foundation

/// An archived show whose calendar day comes round again within the lead window.
struct FootprintAnniversary: Equatable, Identifiable {
    let showID: UUID
    let years: Int
    let month: Int
    let day: Int
    let daysUntil: Int

    var id: UUID { showID }
}

@MainActor
enum FootprintAnniversaryFinder {
    /// The candle lights this many days ahead of the anniversary.
    static let leadDays = 14

    /// Whole-year anniversaries within `leadDays`, nearest first.
    static func upcoming(
        in shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current,
        withinDays: Int = leadDays
    ) -> [FootprintAnniversary] {
        shows.compactMap { anniversary(of: $0, now: now, calendar: calendar) }
            .filter { $0.daysUntil <= withinDays }
            .sorted {
                $0.daysUntil == $1.daysUntil ? $0.years > $1.years : $0.daysUntil < $1.daysUntil
            }
    }

    /// The candle burns for the oldest memory in the window; ties go to the nearest.
    static func featured(in anniversaries: [FootprintAnniversary]) -> FootprintAnniversary? {
        anniversaries.max {
            $0.years == $1.years ? $0.daysUntil > $1.daysUntil : $0.years < $1.years
        }
    }

    /// Other whole-year anniversaries in the featured one's month that have not passed yet.
    static func sameMonth(
        as featured: FootprintAnniversary,
        in shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FootprintAnniversary] {
        shows.compactMap { anniversary(of: $0, now: now, calendar: calendar) }
            .filter { $0.month == featured.month && $0.showID != featured.showID && $0.daysUntil <= 31 }
            .sorted { $0.day < $1.day }
    }

    private static func anniversary(of show: Show, now: Date, calendar: Calendar) -> FootprintAnniversary? {
        let showCalendar = show.timingCalendar(fallback: calendar)
        let parts = showCalendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        guard let showYear = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let today = showCalendar.startOfDay(for: now)
        let thisYear = showCalendar.component(.year, from: today)
        for year in [thisYear, thisYear + 1] {
            guard let occurrence = occurrence(year: year, month: month, day: day, calendar: showCalendar),
                  occurrence >= today else { continue }
            let years = year - showYear
            guard years >= 1,
                  let days = showCalendar.dateComponents([.day], from: today, to: occurrence).day else { return nil }
            return FootprintAnniversary(showID: show.id, years: years, month: month, day: day, daysUntil: days)
        }
        return nil
    }

    /// Feb 29 shows mark their anniversary on Feb 28 in common years.
    private static func occurrence(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        let exact = DateComponents(year: year, month: month, day: day)
        if let date = calendar.date(from: exact),
           calendar.component(.day, from: date) == day {
            return date
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day - 1))
    }
}
