import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningFamiliarityPolicyTests: XCTestCase {
    func testFamiliarityTierBoundaries() {
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 0, totalCount: 100), .firstEncounter)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 1, totalCount: 100), .newListener)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 24, totalCount: 100), .newListener)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 25, totalCount: 100), .gettingIntoIt)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 49, totalCount: 100), .gettingIntoIt)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 50, totalCount: 100), .familiar)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 74, totalCount: 100), .familiar)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 75, totalCount: 100), .deepListener)
        XCTAssertEqual(ListeningFamiliarityTier.resolve(familiarCount: 100, totalCount: 100), .deepListener)
        XCTAssertNil(ListeningFamiliarityTier.resolve(familiarCount: 0, totalCount: 0))
    }

    func testManualThenUndoBecomesUnfamiliar() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let now = Date(timeIntervalSince1970: 100)

        _ = try repository.confirmManualFamiliarity(songID: "song", at: now)
        try repository.undoManualFamiliarity(songID: "song", at: now.addingTimeInterval(1))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FamiliarityEvidenceResolver.isFamiliar(
            songID: "song",
            records: records,
            setlistMemories: []
        ))
    }

    func testManualThenActualThenUndoStaysFamiliar() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let now = Date(timeIntervalSince1970: 100)

        _ = try repository.confirmManualFamiliarity(songID: "song", at: now)
        _ = try repository.confirmActualFamiliarity(songID: "song", at: now.addingTimeInterval(1))
        try repository.undoManualFamiliarity(songID: "song", at: now.addingTimeInterval(2))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.manualConfirmedAt)
        XCTAssertNotNil(record.actualListeningAt)
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "song",
            records: records,
            setlistMemories: []
        ))
    }

    func testManualThenShowRecallThenUndoStaysFamiliar() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let now = Date(timeIntervalSince1970: 100)

        _ = try repository.confirmManualFamiliarity(songID: "song", at: now)
        _ = try repository.addSetlistMemory(
            showID: UUID(),
            catalogSongID: "song",
            at: now.addingTimeInterval(1)
        )
        try repository.undoManualFamiliarity(songID: "song", at: now.addingTimeInterval(2))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let memories = try context.fetch(FetchDescriptor<ShowSetlistMemory>())
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "song",
            records: records,
            setlistMemories: memories
        ))
    }

    func testWantsLiveFreezesAtWholeShowStart() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "Show", date: start, startTime: start)
        context.insert(show)
        let repository = ListeningRepository(modelContext: context)

        try repository.setWantsLive(
            showID: show.id,
            songID: "song",
            isWanted: true,
            at: start.addingTimeInterval(-1)
        )
        XCTAssertThrowsError(try repository.setWantsLive(
            showID: show.id,
            songID: "song",
            isWanted: false,
            at: start
        )) { error in
            XCTAssertEqual(error as? ListeningMutationError, .wantsLiveFrozen(show.id))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
    }

    func testUndatedPostponementKeepsWantsLiveMutable() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let originalStart = Date(timeIntervalSince1970: 100)
        let show = try Show(name: "Postponed", date: originalStart, startTime: originalStart)
        show.changeStatus = .postponed
        show.postponedDate = nil
        context.insert(show)
        let repository = ListeningRepository(modelContext: context)

        try repository.setWantsLive(
            showID: show.id,
            songID: "song",
            isWanted: true,
            at: originalStart.addingTimeInterval(100_000)
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
    }
}
