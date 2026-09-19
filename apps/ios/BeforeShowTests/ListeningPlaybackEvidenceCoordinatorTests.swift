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

    func testFailedPersistenceDoesNotBlockNextSongAndBothRetryWithoutReplay() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        var persistenceAvailable = false
        let coordinator = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard persistenceAvailable else {
                    throw EvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )

        XCTAssertFalse(try coordinator.ingest(full(songID: "song-a", time: 0, observedAt: 0)))
        XCTAssertThrowsError(
            try coordinator.ingest(full(songID: "song-a", time: 51, observedAt: 51))
        )
        XCTAssertThrowsError(
            try coordinator.ingest(full(songID: "song-b", time: 0, observedAt: 52))
        )
        XCTAssertThrowsError(
            try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 103))
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true

        XCTAssertTrue(
            try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 104, isPlaying: false))
        )
        XCTAssertFalse(
            try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 105, isPlaying: false))
        )

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(Set(records.compactMap { $0.actualListeningAt == nil ? nil : $0.songID }), ["song-a", "song-b"])
    }

    func testBatchDrainStopsAtFailureAndDoesNotRetryCommittedItems() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        var persistenceAvailable = false
        var failSongID: String?
        var attempts: [String] = []
        let coordinator = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                attempts.append(songID)
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard persistenceAvailable, failSongID != songID else {
                    throw EvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )

        XCTAssertFalse(try coordinator.ingest(full(songID: "song-a", time: 0, observedAt: 0)))
        XCTAssertThrowsError(try coordinator.ingest(full(songID: "song-a", time: 51, observedAt: 51)))
        XCTAssertThrowsError(try coordinator.ingest(full(songID: "song-b", time: 0, observedAt: 52)))
        XCTAssertThrowsError(try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 103)))

        persistenceAvailable = true
        failSongID = "song-b"
        attempts.removeAll()

        XCTAssertThrowsError(
            try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 104, isPlaying: false))
        )
        XCTAssertEqual(attempts, ["song-a", "song-b"])
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a"]
        )

        failSongID = nil
        attempts.removeAll()
        XCTAssertTrue(try coordinator.flushPending(at: Date(timeIntervalSince1970: 105)))
        XCTAssertEqual(attempts, ["song-b"])
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a", "song-b"]
        )
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

    private func full(
        songID: String = "song-a",
        time: TimeInterval,
        observedAt: TimeInterval,
        isPlaying: Bool = true
    ) -> ListeningPlaybackSample {
        ListeningPlaybackSample(
            songID: songID,
            source: .fullCatalog,
            currentTime: time,
            duration: 100,
            isPlaying: isPlaying,
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }
}

private enum EvidencePersistenceTestError: Error {
    case expectedFailure
}
