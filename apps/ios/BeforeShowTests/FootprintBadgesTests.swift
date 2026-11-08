import Foundation
import XCTest
@testable import BeforeShow

final class FootprintBadgesTests: XCTestCase {
    func testTierAndNextTargetFollowTheLadder() {
        let none = FootprintBadge(family: .merch, progress: 0)
        XCTAssertEqual(none.tier, 0)
        XCTAssertFalse(none.isEarned)
        XCTAssertEqual(none.nextTarget, 1)
        XCTAssertEqual(none.remaining, 1)

        let bronze = FootprintBadge(family: .merch, progress: 4)
        XCTAssertEqual(bronze.tier, 1)
        XCTAssertEqual(bronze.nextTarget, 10)
        XCTAssertEqual(bronze.remaining, 6)
        XCTAssertEqual(bronze.fraction, 3.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(bronze.earnedTierIDs, ["merch-1"])

        let gold = FootprintBadge(family: .merch, progress: 99)
        XCTAssertEqual(gold.tier, 3)
        XCTAssertTrue(gold.isMaxed)
        XCTAssertNil(gold.nextTarget)
        XCTAssertEqual(gold.fraction, 1)
    }

    func testCatalogPutsEarnedFirstThenClosestLocked() {
        var facts = FootprintBadgeFacts()
        facts.merch = 12
        facts.memories = 1
        facts.setlistSongs = 0
        facts.cities = 2
        let badges = FootprintBadgeCatalog.badges(facts)
        XCTAssertEqual(badges.count, FootprintBadgeFamily.allCases.count)
        XCTAssertEqual(Array(badges.prefix(2).map(\.family)), [.merch, .memory])
        // 2/3 cities is the closest locked badge.
        XCTAssertEqual(badges[2].family, .cities)
    }

    func testSeenStoreReportsOnlyNewTiers() throws {
        let suite = "badges-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FootprintBadgeSeenStore(defaults: defaults)

        let first = [FootprintBadge(family: .ticket, progress: 1)]
        XCTAssertEqual(store.unseen(in: first), ["ticket-1"])
        store.markSeen(first)
        XCTAssertTrue(store.unseen(in: first).isEmpty)

        let upgraded = [FootprintBadge(family: .ticket, progress: 10)]
        XCTAssertEqual(store.unseen(in: upgraded), ["ticket-2"])
    }

    @MainActor
    func testFactsCountOnlyArchivedShows() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let archived = try Show(name: "A", date: date, startTime: date, city: "杭州", venueName: "MAO", artists: [ArtistSlot(name: "房东的猫")])
        try archived.setSpending(ticketPrice: 100, travelCost: nil)
        archived.rating = 5
        archived.markEnded(at: date.addingTimeInterval(3 * 3600))
        let other = UUID()
        let archive = FootprintArchiveBuilder.make(shows: [archived])
        XCTAssertEqual(archive.shows.map(\.id), [archived.id])
        let facts = FootprintBadgeCatalog.facts(
            archive: archive,
            memories: [
                ShowSetlistMemory(showID: archived.id, manualTitle: "云烟成雨", manualArtistName: "房东的猫"),
                ShowSetlistMemory(showID: other, manualTitle: "别处", manualArtistName: "X")
            ],
            merch: [MerchItem(showID: archived.id, relativePath: "x"), MerchItem(showID: other, relativePath: "y")],
            fragments: [],
            assets: []
        )
        XCTAssertEqual(facts.setlistSongs, 1)
        XCTAssertEqual(facts.merch, 1)
        XCTAssertEqual(facts.showsWithSpending, 1)
        XCTAssertEqual(facts.ritualRatings, 1)
        XCTAssertEqual(facts.cities, 1)
        XCTAssertEqual(facts.mostSeenArtist, 1)
    }
}
