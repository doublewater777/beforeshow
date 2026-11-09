import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintDemoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    func testEverySampleShowLandsInTheFootprints() throws {
        let shows = try FootprintDemo.shows(now: now)
        let archive = FootprintArchiveBuilder.make(shows: shows, now: now)
        XCTAssertEqual(archive.shows.count, shows.count)
        XCTAssertGreaterThan(archive.cities.count, 3)
        XCTAssertGreaterThanOrEqual(archive.artists.first?.count ?? 0, 3, "a band seen often enough to anchor the sky")
    }

    func testOneSampleIsAboutToHaveItsAnniversary() throws {
        let archive = FootprintArchiveBuilder.make(shows: try FootprintDemo.shows(now: now), now: now)
        XCTAssertNotNil(FootprintAnniversaryFinder.featured(in: FootprintAnniversaryFinder.upcoming(in: archive.shows, now: now)))
    }

    func testTheSampleLivesOnlyInItsOwnMemoryStore() throws {
        let real = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let demo = try FootprintDemo.makeContainer(now: now)
        XCTAssertFalse(try demo.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertTrue(try real.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertTrue(demo.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }

    func testSampleBadgesNeverMarkTheRealBadgesAsSeen() {
        let defaults = FootprintDemo.badgeDefaults()
        XCTAssertNotIdentical(defaults, UserDefaults.standard)
        XCTAssertNil(defaults.stringArray(forKey: FootprintBadgeSeenStore.key))
    }
}
