import XCTest
@testable import BeforeShow

@MainActor
final class FootprintBookTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testBookRunsFromCoverThroughEachYearToTheAfterword() throws {
        let first = try show("柏林护士", date(2021, 7, 3), city: "杭州")
        let second = try show("Nouvelle Vague", date(2021, 11, 14), city: "武汉")
        let third = try show("泡泡岛", date(2023, 10, 2), city: "嘉兴")
        let next = try show("橘子湾", date(2026, 11, 6), city: "福州")

        let book = FootprintBook(archived: [third, first, second], next: next)

        XCTAssertEqual(book.pages, [
            .cover, .contents, .prologue,
            .chapter(year: 2021), .show(first.id), .show(second.id),
            .chapter(year: 2023), .show(third.id),
            .afterword
        ])
        XCTAssertEqual(book.chapters.map(\.number), [1, 2])
        XCTAssertEqual(book.ordinal(of: third), 3)
        XCTAssertNil(book.pageNumber(at: 1), "the contents page is unnumbered")
        XCTAssertEqual(book.pageNumber(at: 2), 2)
        XCTAssertEqual(book.next?.id, next.id)
    }

    func testChaptersNoteNewCitiesAndTheBusiestYear() throws {
        let book = FootprintBook(archived: [
            try show("A", date(2021, 3, 1), city: "杭州"),
            try show("B", date(2022, 4, 1), city: "杭州"),
            try show("C", date(2022, 6, 1), city: "上海"),
            try show("D", date(2022, 9, 1), city: "南京")
        ], next: nil)

        let year2022 = try XCTUnwrap(book.chapter(year: 2022))
        XCTAssertEqual(book.newCities(in: year2022), ["上海", "南京"])
        XCTAssertEqual(book.busiestYear, 2022)
    }

    func testMissedMonthsOnlyWhenTheGapsAreTheException() throws {
        let steady = FootprintBook(archived: try [3, 4, 6, 7].map { try show("S\($0)", date(2024, $0, 10), city: nil) }, next: nil)
        let steadyChapter = try XCTUnwrap(steady.chapters.first)
        XCTAssertEqual(FootprintBook.missedMonths(of: steadyChapter)?.missed, [5])

        let sparse = FootprintBook(archived: try [7, 11].map { try show("P\($0)", date(2021, $0, 10), city: nil) }, next: nil)
        XCTAssertNil(FootprintBook.missedMonths(of: try XCTUnwrap(sparse.chapters.first)), "two shows months apart are not a pattern")
    }

    func testPlacesAndActsAreNamedOnce() throws {
        let day = date(2021, 7, 3)
        let solo = try Show(
            name: "KISS KISS BANG BANG 柏林护士 2021 巡演 杭州站",
            date: day, startTime: day, timeZoneIdentifier: "Asia/Shanghai",
            city: "杭州", venueName: "杭州 MAO Livehouse",
            artists: [ArtistSlot(name: "柏林护士 Berlin Psycho Nurses")]
        )
        XCTAssertEqual(FootprintBookText.place(of: solo), "杭州 MAO Livehouse")
        XCTAssertEqual(FootprintBookText.act(of: solo), "柏林护士 Berlin Psycho Nurses")

        let festival = try Show(
            name: "泡泡岛", date: day, startTime: day, timeZoneIdentifier: "Asia/Shanghai",
            city: "嘉兴", venueName: "湘家荡",
            artists: [ArtistSlot(name: "A"), ArtistSlot(name: "B")]
        )
        XCTAssertEqual(FootprintBookText.place(of: festival), "嘉兴 湘家荡")
        XCTAssertEqual(FootprintBookText.act(of: festival), "泡泡岛")
    }

    func testAChapterAlwaysHasSomethingToSay() throws {
        let shows = try [3, 4, 12].map { month in
            try Show(
                name: "S\(month)", date: date(2023, month, 10), startTime: date(2023, month, 10), timeZoneIdentifier: "Asia/Shanghai",
                city: "杭州", venueName: "MAO", artists: [ArtistSlot(name: "A\(month)")]
            )
        }
        let earlier = try show("First", date(2022, 5, 1), city: "杭州")
        let book = FootprintBook(archived: shows + [earlier], next: nil)
        let chapter = try XCTUnwrap(book.chapter(year: 2023))

        XCTAssertEqual(FootprintBookText.chapterLines(book: book, chapter: chapter).count, 1)
    }

    func testAPostponementWithNoNewDateIsNotTheNextPage() throws {
        let now = date(2026, 11, 4)
        let undated = try show("待定", date(2026, 11, 10), city: nil)
        undated.markPostponed(newDate: nil)
        let dated = try show("橘子湾", date(2026, 11, 20), city: nil)

        XCTAssertEqual(FootprintStagePolicy.nextUpcoming([undated, dated], archived: [], now: now)?.id, dated.id)
        XCTAssertFalse(FootprintStagePolicy.isDated(undated), "the city map's next stop uses the same rule")
        XCTAssertTrue(FootprintStagePolicy.isDated(dated))
    }

    // MARK: Helpers

    private func show(_ name: String, _ day: Date, city: String?) throws -> Show {
        try Show(name: name, date: day, startTime: day.addingTimeInterval(20 * 3600), timeZoneIdentifier: "Asia/Shanghai", city: city)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
