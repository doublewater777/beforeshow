import Foundation

/// One year looked back on: what the book's recap page and the year poster both say.
@MainActor
struct FootprintBookRecap {
    struct Tally: Equatable {
        let name: String
        let count: Int
    }

    let year: Int
    /// Oldest first.
    let shows: [Show]
    let durationMinutes: Int
    let cityCount: Int
    let topArtist: Tally?
    let topVenue: Tally?
    let topCompanion: Tally?
    /// Shows still to come in this year.
    let upcomingCount: Int

    var first: Show? { shows.first }
    var last: Show? { shows.last }

    init(book: FootprintBook, chapter: FootprintBook.Chapter) {
        year = chapter.year
        shows = chapter.shows
        durationMinutes = chapter.shows.reduce(0) { total, show in
            let state = CurrentShowTimeState(show: show, calendar: show.timingCalendar())
            return total + (ShowDurationFormatter.minutes(for: show, timeState: state) ?? 0)
        }
        cityCount = Set(chapter.shows.compactMap(\.bookCity)).count
        topArtist = Self.top(chapter.shows.map { Set($0.artistNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed)) })
        topVenue = Self.top(chapter.shows.map { show in Set([show.bookVenue].compactMap { $0 }) })
        topCompanion = Self.top(chapter.shows.map { Set($0.companionNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed)) })
        upcomingCount = book.upcoming.filter {
            $0.timingCalendar().component(.year, from: $0.effectiveDate) == chapter.year
        }.count
    }

    /// The one name that came up most, at least twice; nil when nothing repeats or two names tie.
    static func top(_ perShow: [Set<String>]) -> Tally? {
        var counts: [String: Int] = [:]
        for names in perShow {
            for name in names { counts[name, default: 0] += 1 }
        }
        guard let best = counts.values.max(), best > 1, counts.values.filter({ $0 == best }).count == 1,
              let name = counts.first(where: { $0.value == best })?.key else { return nil }
        return Tally(name: name, count: best)
    }
}
