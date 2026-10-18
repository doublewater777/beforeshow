import SwiftData
import SwiftUI
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintSearchTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func makeShow(
        _ name: String,
        year: Int,
        artist: String,
        city: String,
        venue: String
    ) throws -> Show {
        let slots = artist
            .components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ArtistSlot(name: $0, avatarURL: nil) }
        return try Show(
            name: name,
            date: date(year, 6, 1),
            startTime: date(year, 6, 1, 19),
            endTime: date(year, 6, 1, 22),
            timeZoneSecondsFromGMT: calendar.timeZone.secondsFromGMT(),
            city: city,
            venueName: venue,
            artists: slots
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testSearchMatchesArtistNameAndSupportsScriptVariants() throws {
        let show1 = try makeShow("现场A", year: 2025, artist: "落日飞车", city: "上海", venue: "MAO")
        let show2 = try makeShow("现场B", year: 2025, artist: "草东没有派对", city: "北京", venue: "糖果")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: show1, query: "落日", filter: .all))
        XCTAssertTrue(FootprintSearchMatcher.matches(show: show1, query: "落日飛車", filter: .all))
        XCTAssertFalse(FootprintSearchMatcher.matches(show: show2, query: "落日", filter: .all))
    }

    func testSearchMatchesShowName() throws {
        let show = try makeShow("夏日入侵企画 巡演", year: 2025, artist: "夏日入侵企画", city: "上海", venue: "MAO")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: show, query: "巡演", filter: .all))
        XCTAssertFalse(FootprintSearchMatcher.matches(show: show, query: "冬季", filter: .all))
    }

    func testSearchMatchesCityAndVenue() throws {
        let show = try makeShow("专场", year: 2025, artist: "陈绮贞", city: "上海", venue: "梅赛德斯-奔驰文化中心")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: show, query: "上海", filter: .all))
        XCTAssertTrue(FootprintSearchMatcher.matches(show: show, query: "梅赛德斯", filter: .all))
        XCTAssertTrue(FootprintSearchMatcher.matches(show: show, query: "奔驰", filter: .all))
        XCTAssertFalse(FootprintSearchMatcher.matches(show: show, query: "鸟巢", filter: .all))
    }

    func testSearchMatchesYearInQuery() throws {
        let show2024 = try makeShow("2024专场", year: 2024, artist: "安溥", city: "台北", venue: "小巨蛋")
        let show2025 = try makeShow("2025专场", year: 2025, artist: "安溥", city: "台北", venue: "小巨蛋")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: show2024, query: "2024", filter: .all))
        XCTAssertFalse(FootprintSearchMatcher.matches(show: show2025, query: "2024", filter: .all))
    }

    func testSearchFilterChipsGeneration() throws {
        let show1 = try makeShow("第一场", year: 2025, artist: "艺人1", city: "上海", venue: "场馆1")
        let show2 = try makeShow("第二场", year: 2025, artist: "艺人1", city: "上海", venue: "场馆2")
        let show3 = try makeShow("第三场", year: 2024, artist: "艺人2", city: "北京", venue: "场馆3")
        let show4 = try makeShow("第四场", year: 2023, artist: "艺人3", city: "广州", venue: "场馆4")

        let archive = FootprintArchiveBuilder.make(
            shows: [show1, show2, show3, show4],
            now: date(2026, 1, 1),
            calendar: calendar
        )

        let chips = FootprintSearchMatcher.filterChips(for: archive)
        XCTAssertEqual(chips.count, 5)
        XCTAssertEqual(chips[0], .all)
        XCTAssertEqual(chips[1], .year(2025))
        XCTAssertEqual(chips[2], .year(2024))
        XCTAssertEqual(chips[3], .city("上海"))
        XCTAssertEqual(chips[4], .city("北京"))
    }

    func testSearchCombinesKeywordAndFilter() throws {
        let shanghai2025 = try makeShow("上海夏日", year: 2025, artist: "草莓", city: "上海", venue: "梅奔")
        let beijing2025 = try makeShow("北京夏日", year: 2025, artist: "草莓", city: "北京", venue: "工体")
        let shanghai2024 = try makeShow("上海秋日", year: 2024, artist: "草莓", city: "上海", venue: "MAO")

        let shows = [shanghai2025, beijing2025, shanghai2024]

        // Keyword only
        let allStrawberry = FootprintSearchMatcher.filterShows(shows, query: "草莓", filter: .all)
        XCTAssertEqual(allStrawberry.count, 3)

        // Keyword + City filter
        let shanghaiStrawberry = FootprintSearchMatcher.filterShows(shows, query: "草莓", filter: .city("上海"))
        XCTAssertEqual(shanghaiStrawberry.count, 2)
        XCTAssertTrue(shanghaiStrawberry.contains(where: { $0.name == "上海夏日" }))
        XCTAssertTrue(shanghaiStrawberry.contains(where: { $0.name == "上海秋日" }))

        // Keyword + Year filter
        let y2025Strawberry = FootprintSearchMatcher.filterShows(shows, query: "草莓", filter: .year(2025))
        XCTAssertEqual(y2025Strawberry.count, 2)
        XCTAssertTrue(y2025Strawberry.contains(where: { $0.name == "上海夏日" }))
        XCTAssertTrue(y2025Strawberry.contains(where: { $0.name == "北京夏日" }))

        // Keyword + non-matching filter
        let beijing2024 = FootprintSearchMatcher.filterShows(shows, query: "秋日", filter: .city("北京"))
        XCTAssertTrue(beijing2024.isEmpty)
    }

    func testSearchEmptyQueryReturnsAllFilteredShows() throws {
        let show1 = try makeShow("现场1", year: 2025, artist: "艺人A", city: "上海", venue: "场馆A")
        let show2 = try makeShow("现场2", year: 2024, artist: "艺人B", city: "北京", venue: "场馆B")
        let shows = [show1, show2]

        let all = FootprintSearchMatcher.filterShows(shows, query: "", filter: .all)
        XCTAssertEqual(all.count, 2)

        let yearFiltered = FootprintSearchMatcher.filterShows(shows, query: "   ", filter: .year(2025))
        XCTAssertEqual(yearFiltered.count, 1)
        XCTAssertEqual(yearFiltered.first?.name, "现场1")
    }

    func testSearchHandlesFestivalMultiArtistLineup() throws {
        let festival = try makeShow("草莓音乐节", year: 2025, artist: "五条人、重塑雕像的权利、万能青年旅店", city: "武汉", venue: "园博园")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: festival, query: "五条人", filter: .all))
        XCTAssertTrue(FootprintSearchMatcher.matches(show: festival, query: "重塑", filter: .all))
        XCTAssertTrue(FootprintSearchMatcher.matches(show: festival, query: "万青", filter: .all) == false)
        XCTAssertTrue(FootprintSearchMatcher.matches(show: festival, query: "万能青年旅店", filter: .all))
    }

    func testSearchEmptyArchiveReturnsAllChipOnly() {
        let archive = FootprintArchiveBuilder.make(shows: [], now: date(2026, 1, 1), calendar: calendar)

        let chips = FootprintSearchMatcher.filterChips(for: archive)
        XCTAssertEqual(chips, [FootprintSearchFilter.all])
    }

    func testSearchFilterMatchesCityWithWhitespace() throws {
        let show = try makeShow("现场", year: 2025, artist: "艺人", city: " 上海 ", venue: "MAO")

        XCTAssertTrue(FootprintSearchMatcher.matches(show: show, query: "", filter: .city("上海")))
        XCTAssertFalse(FootprintSearchMatcher.matches(show: show, query: "", filter: .city("北京")))
    }

    func testSearchSubtitleFormatting() throws {
        let withAll = try makeShow("现场1", year: 2025, artist: "艺人", city: "上海", venue: "MAO")
        let formattedWithAll = FootprintSearchMatcher.subtitle(for: withAll)
        XCTAssertTrue(formattedWithAll.contains("上海 · MAO"))
        XCTAssertTrue(formattedWithAll.contains("06.01"))

        let withoutVenue = try Show(
            name: "现场2",
            date: date(2025, 6, 1),
            startTime: date(2025, 6, 1, 19),
            endTime: date(2025, 6, 1, 22),
            timeZoneSecondsFromGMT: calendar.timeZone.secondsFromGMT(),
            city: "上海",
            venueName: nil
        )
        let formattedWithoutVenue = FootprintSearchMatcher.subtitle(for: withoutVenue)
        XCTAssertEqual(formattedWithoutVenue, "上海 · 06.01")

        let withoutCityAndVenue = try Show(
            name: "现场3",
            date: date(2025, 6, 1),
            startTime: date(2025, 6, 1, 19),
            endTime: date(2025, 6, 1, 22),
            timeZoneSecondsFromGMT: calendar.timeZone.secondsFromGMT(),
            city: nil,
            venueName: nil
        )
        let formattedWithoutCityAndVenue = FootprintSearchMatcher.subtitle(for: withoutCityAndVenue)
        XCTAssertEqual(formattedWithoutCityAndVenue, "06.01")
    }
}
