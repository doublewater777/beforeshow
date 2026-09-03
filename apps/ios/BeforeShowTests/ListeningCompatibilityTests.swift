import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningCompatibilityTests: XCTestCase {
    func testArtistSlotDecodesPreArtistIDPayload() throws {
        let data = Data(#"{"name":"Artist","avatarURL":null,"appleMusicURL":"https://music.apple.com/cn/artist/name/123","albumArtworkURL":null}"#.utf8)

        let decoded = try JSONDecoder().decode(ArtistSlot.self, from: data)

        XCTAssertEqual(decoded.name, "Artist")
        XCTAssertEqual(decoded.appleMusicURL, "https://music.apple.com/cn/artist/name/123")
        XCTAssertNil(decoded.appleMusicArtistID)
    }

    func testManualUndoDoesNotRemoveActualEvidence() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let manualAt = Date(timeIntervalSince1970: 100)
        let actualAt = Date(timeIntervalSince1970: 200)

        _ = try repository.confirmManualFamiliarity(songID: "song", at: manualAt)
        _ = try repository.confirmActualFamiliarity(songID: "song", at: actualAt)
        try repository.undoManualFamiliarity(songID: "song", at: Date(timeIntervalSince1970: 300))
        try context.save()

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let stored = try XCTUnwrap(records.first)
        XCTAssertNil(stored.manualConfirmedAt)
        XCTAssertEqual(stored.actualListeningAt, actualAt)
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "song",
            records: records,
            setlistMemories: []
        ))
    }

    func testOrphanRepairRemovesOnlyShowScopedListeningRows() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let missingShowID = UUID()
        let now = Date()
        context.insert(ShowWantsLiveSong(showID: missingShowID, songID: "song"))
        context.insert(ShowArtistListeningPreference(showID: missingShowID, artistID: "artist", isExcluded: true))
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: missingShowID,
            effectiveStartAtCapture: now,
            familiarSongIDsAtCapture: ["song"]
        ))
        context.insert(ShowOpeningArtistTier(
            showID: missingShowID,
            artistID: "artist",
            artistNameAtCapture: "Artist",
            tierRawValue: "familiar",
            baselineCapturedAt: now,
            catalogSnapshotFetchedAt: now
        ))
        context.insert(ShowSetlistMemory(showID: missingShowID, catalogSongID: "song"))
        context.insert(SongFamiliarityRecord(songID: "song", actualListeningAt: now))
        context.insert(CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist"))
        try context.save()

        try ListeningShowDataCleaner.deleteOrphans(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 1)
    }
}
