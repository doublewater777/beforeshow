import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class DynamicCoverRetirementTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DynamicCoverRetirementTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRetirementDeletesOldCoversAndKeepsShows() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "旧现场", date: start, startTime: start)
        let cover = DynamicCover(showID: show.id, relativePath: "\(show.id.uuidString)/video.mov", contentTypeIdentifier: "public.movie", videoDuration: 3)
        context.insert(show)
        context.insert(cover)
        show.dynamicCover = cover
        try context.save()
        defaults.set(true, forKey: DynamicCoverRetirement.faceKeyPrefix + show.id.uuidString)
        defaults.set(Data([1]), forKey: DynamicCoverRetirement.pendingCleanupKey)

        DynamicCoverRetirement.retireIfNeeded(in: context, defaults: defaults)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DynamicCover>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Show>()), 1)
        XCTAssertNil(show.dynamicCover)
        XCTAssertNil(defaults.object(forKey: DynamicCoverRetirement.faceKeyPrefix + show.id.uuidString))
        XCTAssertNil(defaults.object(forKey: DynamicCoverRetirement.pendingCleanupKey))
        XCTAssertTrue(defaults.bool(forKey: DynamicCoverRetirement.completedKey))
    }

    func testRetirementRunsOnce() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        defaults.set(true, forKey: DynamicCoverRetirement.completedKey)
        let showID = UUID()
        context.insert(DynamicCover(showID: showID, relativePath: "\(showID.uuidString)/video.mov", contentTypeIdentifier: "public.movie", videoDuration: 3))
        try context.save()

        DynamicCoverRetirement.retireIfNeeded(in: context, defaults: defaults)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DynamicCover>()), 1)
    }
}
