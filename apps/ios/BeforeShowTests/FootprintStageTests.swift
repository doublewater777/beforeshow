import CoreGraphics
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintStageTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    // MARK: Anniversary

    func testAnniversaryCountsWholeYearsAndDaysAheadInTheShowsTimeZone() throws {
        let show = try makeShow("I Mean Us", 2021, 11, 14)
        let now = date(2026, 11, 3, 9)

        let found = FootprintAnniversaryFinder.upcoming(in: [show], now: now, calendar: calendar)

        XCTAssertEqual(found, [FootprintAnniversary(showID: show.id, years: 5, month: 11, day: 14, daysUntil: 11)])
    }

    func testAnniversaryOutsideTheLeadWindowAndFirstYearShowsStayDark() throws {
        let farAway = try makeShow("远", 2021, 12, 30)
        let thisYear = try makeShow("今年", 2026, 11, 10)
        let now = date(2026, 11, 3, 9)

        XCTAssertTrue(FootprintAnniversaryFinder.upcoming(in: [farAway, thisYear], now: now, calendar: calendar).isEmpty)
    }

    func testFeaturedAnniversaryIsTheOldestMemoryAndTheRestOfTheMonthIsListed() throws {
        let older = try makeShow("I Mean Us", 2021, 11, 14)
        let nearer = try makeShow("美秀集團", 2024, 11, 9)
        let later = try makeShow("一枚钉", 2025, 11, 23)
        let now = date(2026, 11, 3, 9)

        let upcoming = FootprintAnniversaryFinder.upcoming(in: [older, nearer, later], now: now, calendar: calendar)
        let featured = try XCTUnwrap(FootprintAnniversaryFinder.featured(in: upcoming))
        let others = FootprintAnniversaryFinder.sameMonth(as: featured, in: [older, nearer, later], now: now, calendar: calendar)

        XCTAssertEqual(featured.showID, older.id)
        XCTAssertEqual(others.map(\.showID), [nearer.id, later.id])
        XCTAssertEqual(others.map(\.years), [2, 1])
    }

    func testAnniversaryOnTheDayItselfIsZeroDaysAway() throws {
        let show = try makeShow("当天", 2023, 6, 29)
        let found = FootprintAnniversaryFinder.upcoming(in: [show], now: date(2026, 6, 29, 22), calendar: calendar)
        XCTAssertEqual(found.first?.daysUntil, 0)
        XCTAssertEqual(found.first?.years, 3)
    }

    // MARK: Passport pins

    func testPassportPinsCoverFirstOrdinalAwayPeakLatestAndTheNextLockedTarget() throws {
        var shows: [Show] = []
        for index in 0..<12 {
            let year = index < 3 ? 2023 : 2024
            shows.append(try makeShow("场\(index + 1)", year, 1 + index % 12, 5, city: index == 4 ? "上海" : "杭州"))
        }

        let pins = FootprintMilestoneBuilder.make(shows: shows)

        XCTAssertEqual(pins.map(\.kind), [
            .first,
            .ordinal(10),
            .firstAway(city: "上海"),
            .peakYear(year: 2024, count: 9),
            .latest(12),
            .locked(target: 25, remaining: 13)
        ])
        XCTAssertNil(pins.last?.showID)
    }

    func testPassportSkipsAwayAndPeakPinsWhenThereIsNothingToCompare() throws {
        let shows = [try makeShow("唯一", 2025, 3, 7)]
        XCTAssertEqual(FootprintMilestoneBuilder.make(shows: shows).map(\.kind), [
            .first,
            .locked(target: 10, remaining: 9)
        ])
    }

    // MARK: Constellation

    func testConstellationLinksSharedBillsAndLeavesSoloRepeatsAsLoneStars() throws {
        let shows = [
            try makeShow("零食决斗", 2022, 12, 17, artists: ["奥利不服", "浪味仙贝"]),
            try makeShow("吟游拓荒", 2025, 3, 7, artists: ["旧日的派珀", "夜晚做决定", "浪味仙贝"]),
            try makeShow("凛歌", 2026, 6, 6, artists: ["午夜乒乓", "旧日的派珀", "浪味仙贝"]),
            try makeShow("许钧一", 2024, 3, 8, artists: ["许钧"]),
            try makeShow("许钧二", 2024, 12, 14, artists: ["许钧"]),
            try makeShow("路人", 2023, 4, 18, artists: ["LUCY"])
        ]

        let sky = FootprintConstellationBuilder.make(shows: shows)
        let byName = Dictionary(uniqueKeysWithValues: sky.stars.map { ($0.name, $0) })

        XCTAssertEqual(byName["浪味仙贝"]?.count, 3)
        XCTAssertEqual(byName["许钧"]?.isLone, true)
        XCTAssertEqual(byName["浪味仙贝"]?.isLone, false)
        XCTAssertNil(byName["LUCY"], "single-show artists with no shared bill are background dust")
        XCTAssertEqual(sky.dustCount, 1)
        XCTAssertTrue(sky.edges.contains(FootprintConstellation.Edge(from: "奥利不服", to: "浪味仙贝")))
        XCTAssertEqual(sky.groups.map(\.brightest), ["浪味仙贝"])
    }

    func testConstellationLayoutIsDeterministicAndStaysInsideTheSky() throws {
        let names = (0..<18).map { "艺人\($0)" }
        let edges = zip(names, names.dropFirst()).map { FootprintConstellation.Edge(from: $0, to: $1) }

        let first = FootprintConstellationBuilder.layout(names: names, edges: edges)
        let second = FootprintConstellationBuilder.layout(names: names, edges: edges)

        XCTAssertEqual(first, second)
        for point in first.values {
            XCTAssertTrue((0.09...0.91).contains(point.x) && (0.09...0.91).contains(point.y), "\(point)")
        }
    }

    // MARK: Neon and marquee

    func testNeonSteadinessFollowsHowLongAgoTheLastVisitWas() {
        XCTAssertEqual(FootprintStagePolicy.steadiness(daysSinceLast: 150), .steady)
        XCTAssertEqual(FootprintStagePolicy.steadiness(daysSinceLast: 400), .flickering)
        XCTAssertEqual(FootprintStagePolicy.steadiness(daysSinceLast: 820), .failing)
        XCTAssertEqual(FootprintStagePolicy.glow(count: 7, top: 7), .full)
        XCTAssertEqual(FootprintStagePolicy.glow(count: 3, top: 7), .warm)
        XCTAssertEqual(FootprintStagePolicy.glow(count: 2, top: 7), .faint)
    }

    func testMarqueeCountsDaysSinceTheLastShowAndFindsTheNextOne() throws {
        let last = try makeShow("泡泡岛", 2026, 10, 3)
        let next = try makeShow("由你现场", 2026, 11, 7)
        let archived = [last]

        let status = FootprintStagePolicy.marquee(
            archived: archived,
            allShows: [last, next],
            now: date(2026, 11, 3, 9),
            calendar: calendar
        )

        XCTAssertEqual(status.daysSinceLast, 31)
        XCTAssertEqual(status.nextShowID, next.id)
        XCTAssertEqual(status.nextMonth, 11)
        XCTAssertEqual(status.nextDay, 7)
    }

    // MARK: Helpers

    private func makeShow(
        _ name: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        city: String = "杭州",
        artists: [String] = []
    ) throws -> Show {
        try Show(
            name: name,
            date: date(year, month, day),
            startTime: date(year, month, day, 20),
            timeZoneIdentifier: "Asia/Shanghai",
            city: city,
            artists: artists.map { ArtistSlot(name: $0) }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
