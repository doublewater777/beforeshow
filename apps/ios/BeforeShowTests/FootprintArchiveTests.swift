import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintArchiveTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testArchiveIncludesOnlyEndedScheduledShows() throws {
        let ended = try makeShow("已结束", year: 2025, artist: "落日飞车", city: "上海", venue: "MAO")
        let upcoming = try makeShow("未开始", year: 2027, artist: "陈绮贞", city: "杭州", venue: "奥体")
        let canceled = try makeShow("已取消", year: 2025, artist: "新裤子", city: "南京", venue: "奥体")
        canceled.markCanceled()

        let archive = FootprintArchiveBuilder.make(
            shows: [ended, upcoming, canceled],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.shows.map(\.name), ["已结束"])
        XCTAssertEqual(archive.artists, [FootprintRankItem(name: "落日飞车", count: 1)])
    }

    func testArchiveRanksArtistsCitiesVenuesAndSplitsFestivalLineup() throws {
        let first = try makeShow("第一场", year: 2024, artist: "落日飞车、陈绮贞", city: " 上海 ", venue: "MAO")
        let second = try makeShow("第二场", year: 2025, artist: "落日飞车", city: "上海", venue: "梅奔")

        let archive = FootprintArchiveBuilder.make(
            shows: [second, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.artists.first, FootprintRankItem(name: "落日飞车", count: 2))
        XCTAssertEqual(archive.cities, [FootprintRankItem(name: "上海", count: 2)])
        XCTAssertEqual(archive.venues.count, 2)
        XCTAssertEqual(archive.years.map(\.year), [2025, 2024])
        XCTAssertEqual(archive.firstShow?.name, "第一场")
    }

    func testArchiveIncludesACompletedDatedPostponement() throws {
        let postponed = try makeShow("延期后实际演出", year: 2024, artist: "落日飞车", city: "上海", venue: "MAO")
        postponed.markPostponed(newDate: date(2025, 7, 1))

        let archive = FootprintArchiveBuilder.make(
            shows: [postponed],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.shows.map(\.name), ["延期后实际演出"])
    }

    func testArtistRankingPreservesSlashNamesAndDeduplicatesWithinOneShow() throws {
        let show = try makeShow("艺人拆分边界", year: 2024, artist: "AC/DC、A / B、A", city: "上海", venue: "MAO")
        show.markEnded(at: date(2024, 7, 2))

        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(Set(archive.artists), Set([
            FootprintRankItem(name: "A", count: 1),
            FootprintRankItem(name: "B", count: 1),
            FootprintRankItem(name: "AC/DC", count: 1)
        ]))
    }

    func testHistoricalBackfillPreservesCurrentSelectionAndNotificationFocus() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let future = try makeShow("未来现场", year: 2027, artist: "未来艺人", city: "上海", venue: "MAO")
        let selection = CurrentShowSelection(selectedShowID: future.id)
        let notificationState = NotificationSchedulingState(focusedShowID: future.id)
        context.insert(future)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let historical = try makeShow("补录现场", year: 2024, artist: "过去艺人", city: "北京", venue: "工体")
        XCTAssertNil(
            try AddShowPersistenceCoordinator.persist(
                historical,
                intent: .historicalBackfill,
                selections: [selection],
                notificationStates: [notificationState],
                in: context
            )
        )

        XCTAssertEqual(selection.selectedShowID, future.id)
        XCTAssertEqual(notificationState.focusedShowID, future.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 2)
    }

    func testArchiveShareCopyIsSpecificToEveryCategory() throws {
        let first = try makeShow("第一场", year: 2024, artist: "落日飞车、陈绮贞", city: "上海", venue: "MAO")
        let second = try makeShow("第二场", year: 2025, artist: "落日飞车", city: "杭州", venue: "奥体")
        let archive = FootprintArchiveBuilder.make(
            shows: [second, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let overview = FootprintArchiveShareCopy.text(for: .overview, archive: archive)
        let artist = FootprintArchiveShareCopy.text(for: .artist, archive: archive)
        let city = FootprintArchiveShareCopy.text(for: .city, archive: archive)
        let venue = FootprintArchiveShareCopy.text(for: .venue, archive: archive)

        XCTAssertEqual(Set([overview, artist, city, venue]).count, 4)
        XCTAssertTrue(overview.contains("2 场现场"))
        XCTAssertTrue(artist.contains("艺人排行：落日飞车 2 场"))
        XCTAssertTrue(city.contains("城市排行："))
        XCTAssertTrue(city.contains("上海 1 场"))
        XCTAssertTrue(city.contains("杭州 1 场"))
        XCTAssertTrue(venue.contains("场馆排行："))
        XCTAssertTrue(venue.contains("MAO 1 场"))
        XCTAssertTrue(venue.contains("奥体 1 场"))
    }

    private func makeShow(
        _ name: String,
        year: Int,
        artist: String,
        city: String,
        venue: String
    ) throws -> Show {
        try Show(
            name: name,
            date: date(year, 6, 1),
            startTime: date(year, 6, 1, 19),
            endTime: date(year, 6, 1, 22),
            city: city,
            venueName: venue,
            artist: artist
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
