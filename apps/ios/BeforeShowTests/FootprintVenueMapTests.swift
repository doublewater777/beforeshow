import XCTest
@testable import BeforeShow

@MainActor
final class FootprintVenueMapTests: XCTestCase {
    func testShowsAtTheSameVenueShareOneSpotNewestFirst() throws {
        let older = try makeShow("吟游拓荒", day: 1, city: "杭州", venue: "MAO Livehouse", address: "杭州市西湖区文三路")
        let newer = try makeShow("凛歌", day: 30, city: "杭州", venue: "mao livehouse ")
        let elsewhere = try makeShow("泡泡岛", day: 10, city: "嘉兴", venue: "槜李湖公园")
        let noVenue = try makeShow("无场馆", day: 5, city: "上海", venue: nil)

        let spots = FootprintVenueMapPolicy.spots(from: [newer, elsewhere, older, noVenue])

        XCTAssertEqual(spots.count, 3)
        let mao = try XCTUnwrap(spots.first { $0.venue?.lowercased() == "mao livehouse" })
        XCTAssertEqual(mao.showIDs, [newer.id, older.id])
        XCTAssertEqual(mao.query, "杭州市西湖区文三路", "an address beats the venue name for the lookup")
        XCTAssertEqual(spots.first { $0.venue == "槜李湖公园" }?.query, "嘉兴 槜李湖公园")
        XCTAssertNil(spots.first { $0.city == "上海" }?.query, "a city-only spot sits on the city")
        XCTAssertEqual(spots.map(\.city), ["杭州", "上海", "嘉兴"], "ordered by first visit")
    }

    func testNearbySpotsStackWhenZoomedOutAndSplitWhenZoomedIn() throws {
        let a = spot("a", shows: 3)
        let b = spot("b", shows: 1)
        let c = spot("c", shows: 1)
        let placed = [(a, 30.27, 120.15), (b, 30.30, 120.10), (c, 31.23, 121.47)]
            .map { (spot: $0.0, latitude: $0.1, longitude: $0.2) }

        let far = FootprintVenueMapPolicy.clusters(placed, cell: 0.5)
        XCTAssertEqual(far.count, 2)
        XCTAssertEqual(far.first { $0.spots.count == 2 }?.lead.id, "a", "the busier venue leads the stack")
        XCTAssertEqual(far.first { $0.spots.count == 2 }?.showCount, 4)

        let near = FootprintVenueMapPolicy.clusters(placed, cell: 0.01)
        XCTAssertEqual(near.count, 3)
    }

    private func spot(_ id: String, shows: Int) -> FootprintVenueSpot {
        FootprintVenueSpot(id: id, venue: id, city: nil, showIDs: (0..<shows).map { _ in UUID() }, firstDate: Date(timeIntervalSince1970: 0), query: nil)
    }

    private func makeShow(_ name: String, day: Int, city: String, venue: String?, address: String? = nil) throws -> Show {
        let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400)
        return try Show(name: name, date: date, startTime: date, timeZoneIdentifier: "Asia/Shanghai", city: city, venueName: venue, venueAddress: address)
    }
}
