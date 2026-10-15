import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class FootprintListeningMemoryTests: XCTestCase {
    func testHistoricalTierIsFrozenRatherThanLive() throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
        let owner = FootprintListeningCoordinator(context: context, show: show)
        owner.reload()
        XCTAssertEqual(owner.tiers.first { $0.artistID == "a" }?.tierRawValue, "firstEncounter")
        try ListeningRepository(modelContext: context).confirmActualFamiliarity(songID: "a1")
        try context.save()
        owner.reload()
        XCTAssertEqual(owner.tiers.first { $0.artistID == "a" }?.tierRawValue, "firstEncounter")
        XCTAssertNil(ListeningFamiliarityTier(rawValue: "missing"))
    }
}
@MainActor final class ListeningCrossFeatureIntegrationTests: XCTestCase {
    func testShowCleanupPreservesGlobalsAndLocalResetClearsAllListeningTables() throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let repo = ListeningRepository(modelContext: context)
        try repo.confirmActualFamiliarity(songID: "a1")
        context.insert(ShowSetlistMemory(showID: show.id, catalogSongID: "a1"))
        context.insert(ShowWantsLiveSong(showID: show.id, songID: "a1", createdAt: show.date.addingTimeInterval(-100)))
        try repo.setArtistExcluded(showID: show.id, artistID: "a", isExcluded: true)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
        try context.save()
        try ListeningShowDataCleaner.deleteShowScopedData(showID: show.id, in: context)
        context.delete(show); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 3)
        try ListeningLocalDataCleaner.deleteAll(in: context); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 0)
    }
}
