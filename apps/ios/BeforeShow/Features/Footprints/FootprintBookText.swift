import Foundation

/// The sentences the memory book is written in, made from the archive.
@MainActor
enum FootprintBookText {
    static func prologue(book: FootprintBook, archive: FootprintArchiveSnapshot) -> [String] {
        guard let first = book.shows.first else { return [] }
        let where_ = place(of: first)
        let opening = where_.isEmpty
            ? BSLocalization.format("%1$@，你看了%2$@。", longDate(first.effectiveDate, calendar: first.timingCalendar()), act(of: first))
            : BSLocalization.format("%1$@，你在%2$@看了%3$@。", longDate(first.effectiveDate, calendar: first.timingCalendar()), where_, act(of: first))
        guard book.shows.count > 1 else {
            return [opening, BSLocalization.text("这是目前唯一的一场。")]
        }
        let since = BSLocalization.format(
            "之后，你又去了 %1$lld 场，在 %2$lld 个场馆里，一共站了 %3$@。",
            book.shows.count - 1,
            archive.venues.count,
            duration(minutes: archive.totalDurationMinutes)
        )
        return [opening, BSLocalization.text("那是第一场。"), since]
    }

    static func chapterLines(book: FootprintBook, chapter: FootprintBook.Chapter) -> [String] {
        var lines: [String] = []
        let cities = book.newCities(in: chapter)
        if !cities.isEmpty {
            lines.append(BSLocalization.format("这一年，你第一次为现场去了%@。", list(Array(cities.prefix(4)))))
        }
        if let span = FootprintBook.missedMonths(of: chapter) {
            lines.append(span.missed.isEmpty
                ? BSLocalization.format("从%1$@到%2$@，每个月都去了现场。", monthName(span.first), monthName(span.last))
                : BSLocalization.format("从%1$@到%2$@，只有%3$@没去现场。", monthName(span.first), monthName(span.last), list(span.missed.map(monthName)))
            )
        }
        if lines.isEmpty {
            // Nothing new and no pattern to the months: say what the year held.
            let venues = Set(chapter.shows.compactMap(\.bookVenue)).count
            let artists = Set(chapter.shows.flatMap { $0.artistNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed) }).count
            if venues > 0, artists > 0 {
                lines.append(BSLocalization.format("这一年，你在 %1$lld 个场馆见了 %2$lld 位艺人。", venues, artists))
            }
        }
        return lines
    }

    static func afterword(book: FootprintBook) -> [String] {
        guard let last = book.shows.last else { return [] }
        var lines = [
            BSLocalization.format("第 %1$lld 场是 %2$@的%3$@。", book.shows.count, longDate(last.effectiveDate, calendar: last.timingCalendar()), act(of: last)),
            BSLocalization.text("这一册写到这里。")
        ]
        if let next = book.next {
            lines.append(BSLocalization.format("下一页，留给%@。", monthDay(next.effectiveDate, calendar: next.timingCalendar())))
        } else {
            lines.append(BSLocalization.text("下一页，等你写。"))
        }
        return lines
    }

    /// Where a show was, without saying the city twice when the venue already carries it.
    static func place(of show: Show) -> String {
        guard let venue = show.bookVenue else { return show.bookCity ?? "" }
        guard let city = show.bookCity, !venue.contains(city) else { return venue }
        return city + " " + venue
    }

    /// Who you saw: the act for a single-artist show, the show itself for a bill or a festival.
    static func act(of show: Show) -> String {
        let names = show.artistNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed)
        return names.count == 1 ? names[0] : show.name
    }

    /// "距今 5 年 4 个月" from the show's day to today.
    static func elapsed(since date: Date, calendar: Calendar, now: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date, to: now)
        guard (parts.year ?? 0) > 0 || (parts.month ?? 0) > 0 else { return BSLocalization.text("就在这个月") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = (parts.year ?? 0) > 0 ? [.year, .month] : [.month]
        formatter.calendar = calendar
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        return BSLocalization.format("距今 %@", formatter.string(from: components) ?? "")
    }

    static func longDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    static func duration(minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = minutes >= 24 * 60 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(minutes * 60)) ?? ""
    }

    private static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.standaloneMonthSymbols[month - 1]
    }

    private static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }
}
