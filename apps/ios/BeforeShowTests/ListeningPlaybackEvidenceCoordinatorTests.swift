import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningPlaybackEvidenceCoordinatorTests: XCTestCase {
    func testThresholdPersistsActualEvidenceOnlyOnce() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let coordinator = try ListeningPlaybackEvidenceCoordinator(modelContext: context)
        let heardAt = Date(timeIntervalSince1970: 500)

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: heardAt))
        XCTAssertFalse(try coordinator.ingest(full(time: 25, observedAt: 25), at: heardAt))
        XCTAssertTrue(try coordinator.ingest(full(time: 51, observedAt: 51), at: heardAt))
        XCTAssertFalse(try coordinator.ingest(full(time: 75, observedAt: 75), at: heardAt))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.songID, "song-a")
        XCTAssertEqual(records.first?.actualListeningAt, heardAt)
    }

    func testFailedPersistenceRollsBackAndRetriesPendingThreshold() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        var shouldFail = true
        let coordinator = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                if shouldFail {
                    shouldFail = false
                    throw EvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )
        let firstAttempt = Date(timeIntervalSince1970: 500)
        let retryAttempt = Date(timeIntervalSince1970: 501)

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: firstAttempt))
        XCTAssertThrowsError(
            try coordinator.ingest(full(time: 51, observedAt: 51), at: firstAttempt)
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        XCTAssertTrue(
            try coordinator.ingest(full(time: 51, observedAt: 52), at: retryAttempt)
        )
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == "song-a" }
        )
        XCTAssertEqual(record.actualListeningAt, retryAttempt)
    }

    func testManualFamiliarityDoesNotSuppressLaterActualEvidence() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let manualAt = Date(timeIntervalSince1970: 100)
        let actualAt = Date(timeIntervalSince1970: 500)
        context.insert(SongFamiliarityRecord(songID: "song-a", manualConfirmedAt: manualAt))
        try context.save()
        let coordinator = try ListeningPlaybackEvidenceCoordinator(modelContext: context)

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: actualAt))
        XCTAssertTrue(try coordinator.ingest(full(time: 51, observedAt: 51), at: actualAt))

        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SongFamiliarityRecord>()).first)
        XCTAssertEqual(record.manualConfirmedAt, manualAt)
        XCTAssertEqual(record.actualListeningAt, actualAt)
    }

    private func full(time: TimeInterval, observedAt: TimeInterval) -> ListeningPlaybackSample {
        ListeningPlaybackSample(
            songID: "song-a",
            source: .fullCatalog,
            currentTime: time,
            duration: 100,
            isPlaying: true,
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }
}

private enum EvidencePersistenceTestError: Error {
    case expectedFailure
}
