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
        XCTAssertTrue(owner.canRecall)
        XCTAssertEqual(owner.tiers.first { $0.artistID == "a" }?.tierRawValue, "firstEncounter")
        try ListeningRepository(modelContext: context).confirmActualFamiliarity(songID: "a1")
        try context.save()
        owner.reload()
        XCTAssertEqual(owner.tiers.first { $0.artistID == "a" }?.tierRawValue, "firstEncounter")
        XCTAssertNil(ListeningFamiliarityTier(rawValue: "missing"))
    }
}
@MainActor final class ShowSetlistMemoryTests: XCTestCase {
    func testCatalogRecallIsEvidenceAndManualRecallIsNot() throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let owner = FootprintListeningCoordinator(context: context, show: show)
        owner.reload()
        owner.add(title: "Uncatalogued", artist: "A", surprising: true)
        owner.add(songID: "a1", surprising: true)
        XCTAssertEqual(owner.memories.count, 2)
        XCTAssertEqual(owner.memories.filter(\.isMostSurprising).count, 1)
        XCTAssertEqual(FamiliarityEvidenceResolver.familiarSongIDs(records: [], setlistMemories: owner.memories), ["a1"])
        owner.delete(try XCTUnwrap(owner.memories.first { $0.catalogSongID == "a1" }))
        XCTAssertTrue(FamiliarityEvidenceResolver.familiarSongIDs(records: [], setlistMemories: owner.memories).isEmpty)
        owner.add(songID: "a1")
        try ListeningRepository(modelContext: context).confirmActualFamiliarity(songID: "a1")
        try context.save()
        owner.delete(try XCTUnwrap(owner.memories.first { $0.catalogSongID == "a1" }))
        XCTAssertEqual(FamiliarityEvidenceResolver.familiarSongIDs(records: try context.fetch(FetchDescriptor<SongFamiliarityRecord>()), setlistMemories: owner.memories), ["a1"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 1)
    }
}
@MainActor final class ListeningCrossFeatureIntegrationTests: XCTestCase {
    func testShowCleanupPreservesGlobalsAndLocalResetClearsAllListeningTables() throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let repo = ListeningRepository(modelContext: context)
        try repo.confirmActualFamiliarity(songID: "a1")
        try repo.addSetlistMemory(showID: show.id, catalogSongID: "a1")
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
