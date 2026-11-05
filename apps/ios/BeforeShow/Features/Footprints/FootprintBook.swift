import Foundation

/// The memory book: the archive told as a book — a cover, contents, a preface, a chapter
/// for every year with a page for each show in it, and an afterword that leaves the next page open.
@MainActor
struct FootprintBook {
    enum Page: Hashable {
        case cover
        case contents
        case prologue
        case chapter(year: Int)
        case show(UUID)
        case afterword
    }

    struct Chapter {
        let number: Int
        let year: Int
        /// Oldest first.
        let shows: [Show]
    }

    /// Oldest first; a show's ordinal is its place here.
    let shows: [Show]
    let chapters: [Chapter]
    let pages: [Page]
    /// The next show you have a ticket for, the page the book leaves open.
    let next: Show?

    init(archived: [Show], next: Show?) {
        let ordered = FootprintArchiveRankingBuilder.chronological(archived)
        shows = ordered
        var byYear: [(year: Int, shows: [Show])] = []
        for show in ordered {
            let year = show.timingCalendar().component(.year, from: show.effectiveDate)
            if byYear.last?.year == year {
                byYear[byYear.count - 1].shows.append(show)
            } else {
                byYear.append((year, [show]))
            }
        }
        chapters = byYear.enumerated().map { Chapter(number: $0.offset + 1, year: $0.element.year, shows: $0.element.shows) }
        pages = [.cover, .contents, .prologue]
            + chapters.flatMap { [Page.chapter(year: $0.year)] + $0.shows.map { Page.show($0.id) } }
            + [.afterword]
        self.next = next
    }

    func index(of page: Page) -> Int? { pages.firstIndex(of: page) }

    /// Printed at the foot of a page; the cover and contents are unnumbered.
    func pageNumber(at index: Int) -> Int? { index >= 2 ? index : nil }

    func ordinal(of show: Show) -> Int {
        (shows.firstIndex { $0.id == show.id } ?? 0) + 1
    }

    func show(id: UUID) -> Show? { shows.first { $0.id == id } }

    func chapter(year: Int) -> Chapter? { chapters.first { $0.year == year } }

    func chapter(containing show: Show) -> Chapter? {
        chapters.first { $0.shows.contains { $0.id == show.id } }
    }

    /// The year you went out most, when there is one clear year.
    var busiestYear: Int? {
        let counts = chapters.map(\.shows.count)
        guard chapters.count > 1, let top = counts.max(), counts.filter({ $0 == top }).count == 1 else { return nil }
        return chapters.first { $0.shows.count == top }?.year
    }

    /// Cities a chapter visited for the first time in the book, in the order you first went.
    func newCities(in chapter: Chapter) -> [String] {
        var seen = Set<String>()
        for earlier in chapters where earlier.year < chapter.year {
            earlier.shows.compactMap(\.bookCity).forEach { seen.insert($0) }
        }
        var found: [String] = []
        for city in chapter.shows.compactMap(\.bookCity) where !seen.contains(city) {
            seen.insert(city)
            found.append(city)
        }
        return found
    }

    static func monthCounts(of chapter: Chapter) -> [Int] {
        var counts = Array(repeating: 0, count: 12)
        for show in chapter.shows {
            counts[show.timingCalendar().component(.month, from: show.effectiveDate) - 1] += 1
        }
        return counts
    }

    /// The months between a chapter's first and last show that had none, when it reads as a pattern:
    /// nil if the year is too short to say anything, empty if no month was missed.
    static func missedMonths(of chapter: Chapter) -> (first: Int, last: Int, missed: [Int])? {
        let counts = monthCounts(of: chapter)
        guard let first = counts.firstIndex(where: { $0 > 0 }),
              let last = counts.lastIndex(where: { $0 > 0 }),
              last - first >= 3 else { return nil }
        let missed = (first...last).filter { counts[$0] == 0 }
        // Only worth saying when the gaps are the exception.
        guard missed.count <= 2, missed.count * 2 < last - first + 1 else { return nil }
        return (first + 1, last + 1, missed.map { $0 + 1 })
    }
}

extension Show {
    var bookCity: String? { FootprintTextNormalizer.nonEmptyTrimmed(city) }
    var bookVenue: String? { FootprintTextNormalizer.nonEmptyTrimmed(venueName) }
}
