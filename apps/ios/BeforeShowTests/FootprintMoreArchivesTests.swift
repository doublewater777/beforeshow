import Foundation
import XCTest
@testable import BeforeShow

final class FootprintMoreArchivesTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 20))!
    }

    private func show(_ name: String, _ date: Date, artists: [String] = [], companions: [String] = []) throws -> Show {
        try Show(
            name: name,
            date: date,
            startTime: date,
            timeZoneIdentifier: "Asia/Shanghai",
            artists: artists.map { ArtistSlot(name: $0) },
            companionStatus: companions.isEmpty ? .none : .confirmed,
            companionNames: companions
        )
    }

    private func memory(_ show: Show, _ title: String, _ artist: String, id: String? = nil) -> ShowSetlistMemory {
        ShowSetlistMemory(showID: show.id, catalogSongID: id, manualTitle: title, manualArtistName: artist)
    }

    // MARK: Setlist

    func testSetlistCountsDistinctShowsAndOrdersByMostHeard() throws {
        let a = try show("A", day(2021, 11, 20)), b = try show("B", day(2023, 3, 17)), c = try show("C", day(2026, 10, 3))
        let memories = [
            memory(a, "云烟成雨", "房东的猫", id: "1"), memory(b, "云烟成雨", "房东的猫", id: "1"), memory(c, "云烟成雨", "房东的猫", id: "1"),
            memory(a, "下一站茶山刘", "房东的猫"), memory(b, " 下一站茶山刘", "房东的猫"),
            memory(c, "七里香", "周杰伦"),
            memory(c, "七里香", "周杰伦"),
        ]
        let other = UUID()
        let songs = FootprintSetlistArchive.songs(
            memories: memories + [ShowSetlistMemory(showID: other, manualTitle: "不在归档", manualArtistName: "X")],
            shows: [a, b, c]
        )
        XCTAssertEqual(songs.map(\.title), ["云烟成雨", "下一站茶山刘", "七里香"])
        XCTAssertEqual(songs.map(\.count), [3, 2, 1])
        XCTAssertEqual(songs.first?.showIDs, [a.id, b.id, c.id])

        XCTAssertEqual(FootprintSetlistArchive.list(songs, tab: .once).map(\.title), ["七里香"])
        XCTAssertEqual(FootprintSetlistArchive.list(songs, tab: .artist).map(\.artistName), ["房东的猫", "房东的猫", "周杰伦"])
    }

    // MARK: Companions

    func testCompanionBandsCountSharedShowsAndTopArtist() throws {
        let a = try show("A", day(2021, 7, 17), artists: ["浪味仙贝"], companions: ["小鹿"])
        let b = try show("B", day(2024, 4, 11), artists: ["浪味仙贝", "午夜乒乓"], companions: ["小鹿", "阿杰"])
        let c = try show("C", day(2025, 12, 5), artists: ["午夜乒乓"], companions: ["阿杰"])
        let solo = try show("D", day(2025, 1, 1), artists: ["浪味仙贝"])
        let bands = FootprintCompanionArchive.bands(shows: [a, b, c, solo])
        // Tied counts fall back to name order (pinyin: 阿 before 小).
        XCTAssertEqual(bands.map(\.name), ["阿杰", "小鹿"])
        XCTAssertEqual(bands.map(\.count), [2, 2])
        XCTAssertEqual(bands[1].showIDs, [b.id, a.id])
        XCTAssertEqual(bands[1].topArtist, "浪味仙贝")
        XCTAssertEqual(bands[1].topArtistCount, 2)
        XCTAssertEqual(bands[0].topArtist, "午夜乒乓")
    }

    // MARK: Merch

    func testMerchShelvesGroupByShowYearNewestFirst() throws {
        let a = try show("A", day(2023, 3, 17)), b = try show("B", day(2026, 6, 6)), c = try show("C", day(2026, 10, 3))
        let items = [a, b, c, b].map { MerchItem(showID: $0.id, relativePath: "x") }
        let shelves = FootprintMerchArchive.shelves(items: items + [MerchItem(showID: UUID(), relativePath: "x")], shows: [a, b, c])
        XCTAssertEqual(shelves.map(\.year), [2026, 2023])
        XCTAssertEqual(shelves[0].items.map(\.showID), [c.id, b.id, b.id])
    }

    // MARK: Ledger

    func testLedgerTotalsAverageAndExtremes() throws {
        let a = try show("泡泡岛", day(2026, 10, 3)), b = try show("凛歌", day(2026, 6, 6)), c = try show("讯号", day(2026, 4, 19))
        let unrecorded = try show("没记", day(2026, 2, 14)), old = try show("旧", day(2025, 6, 14))
        try a.setSpending(ticketPrice: 680, travelCost: 236, currencyCode: "CNY")
        try b.setSpending(ticketPrice: 380, travelCost: nil, currencyCode: "CNY")
        try c.setSpending(ticketPrice: 280, travelCost: 0, currencyCode: "CNY")
        try old.setSpending(ticketPrice: 580, travelCost: 1120, currencyCode: "CNY")
        let shows = [a, b, c, unrecorded, old]

        XCTAssertEqual(FootprintLedgerArchive.years(shows: shows), [2026, 2025])
        let receipt = FootprintLedgerArchive.receipt(shows: shows, year: 2026)
        XCTAssertEqual(receipt.lines.map(\.name), ["泡泡岛", "凛歌", "讯号"])
        XCTAssertEqual(receipt.ticketSum, 1340)
        XCTAssertEqual(receipt.travelSum, 236)
        XCTAssertEqual(receipt.total, 1576)
        XCTAssertEqual(receipt.average, 525)
        XCTAssertEqual(receipt.mostExpensive?.name, "泡泡岛")
        XCTAssertEqual(receipt.cheapest?.name, "讯号")
        XCTAssertEqual(receipt.unrecordedShowIDs, [unrecorded.id])

        let all = FootprintLedgerArchive.receipt(shows: shows, year: nil)
        XCTAssertEqual(all.lines.count, 4)
        XCTAssertEqual(all.total, 3276)
        XCTAssertEqual(all.mostExpensive?.name, "旧")
    }

    func testLedgerSumsOnlyDominantCurrency() throws {
        let a = try show("A", day(2026, 1, 1)), b = try show("B", day(2026, 2, 1)), c = try show("C", day(2026, 3, 1))
        try a.setSpending(ticketPrice: 100, travelCost: nil, currencyCode: "CNY")
        try b.setSpending(ticketPrice: 200, travelCost: nil, currencyCode: "CNY")
        try c.setSpending(ticketPrice: 50, travelCost: nil, currencyCode: "USD")
        let receipt = FootprintLedgerArchive.receipt(shows: [a, b, c], year: nil)
        XCTAssertEqual(receipt.currencyCode, "CNY")
        XCTAssertEqual(receipt.total, 300)
    }

    // MARK: Current tab record kit

    func testRecordKitSectionsFollowPhase() {
        XCTAssertEqual(CurrentShowRecordKit.kinds(for: .pre), [.ticket, .timetable, .companion])
        XCTAssertEqual(CurrentShowRecordKit.kinds(for: .live), [.memory, .setlist, .companion, .ticket])
        XCTAssertEqual(CurrentShowRecordKit.kinds(for: .ended), [.memory, .setlist, .merch, .spending, .companion, .timetable, .ticket])
        XCTAssertEqual(CurrentShowRecordKit.title(for: .ended), "留下的")
    }

    func testRecordKitRowsReflectRealState() {
        var facts = CurrentShowRecordFacts()
        facts.hasTicket = true
        facts.ticketPriceText = "¥380"
        facts.setlistCount = 3
        let ended = CurrentShowRecordKit.rows(phase: .ended, facts: facts)
        let byKind = Dictionary(uniqueKeysWithValues: ended.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.ticket]?.subtitle, "已保存 1 张 · ¥380")
        XCTAssertEqual(byKind[.setlist]?.action, "›")
        XCTAssertEqual(byKind[.spending]?.subtitle, "票价 ¥380 · 路费还没填")
        XCTAssertEqual(byKind[.spending]?.action, "补上")
        XCTAssertEqual(byKind[.spending]?.emphasizesAction, true)
        XCTAssertEqual(byKind[.merch]?.action, "拍一张")
        XCTAssertEqual(byKind[.merch]?.emphasizesAction, true)

        let live = CurrentShowRecordKit.rows(phase: .live, facts: facts, leading: [.endShow])
        XCTAssertEqual(live.first?.kind, .endShow)
        XCTAssertEqual(live.first { $0.kind == .setlist }?.action, "记一首")
    }
}
