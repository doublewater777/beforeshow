import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningPlaybackEvidenceCoordinatorTests: XCTestCase {
    private var persistenceAvailable = false
    private var failSongID: String?

    func testThresholdPersistsActualEvidenceOnlyOnce() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let coordinator = try ListeningPlaybackEvidenceCoordinator(modelContext: context)
        let heardAt = Date(timeIntervalSince1970: 500)

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: heardAt).committedAny)
        XCTAssertFalse(try coordinator.ingest(full(time: 25, observedAt: 25), at: heardAt).committedAny)
        XCTAssertTrue(try coordinator.ingest(full(time: 51, observedAt: 51), at: heardAt).committedAny)
        XCTAssertFalse(try coordinator.ingest(full(time: 75, observedAt: 75), at: heardAt).committedAny)

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.songID, "song-a")
        XCTAssertEqual(records.first?.actualListeningAt, heardAt)
    }

    func testRecordQueuesEvidenceWithoutPersistingUntilFlush() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let coordinator = try ListeningPlaybackEvidenceCoordinator(modelContext: context)

        XCTAssertEqual(
            coordinator.record(full(time: 0, observedAt: 0)),
            .none
        )
        XCTAssertEqual(
            coordinator.record(full(time: 51, observedAt: 51)),
            .becameFamiliar(songID: "song-a")
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty,
            "record() must remain an in-memory playback side effect"
        )

        let flushed = try coordinator.flushPending()

        XCTAssertEqual(flushed.committedSongIDs, ["song-a"])
        XCTAssertFalse(flushed.hasFailure)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).first?.songID,
            "song-a"
        )
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
        let thresholdAt = Date(timeIntervalSince1970: 500)
        let retryAt = Date(timeIntervalSince1970: 501)

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: thresholdAt).committedAny)
        let failed = try coordinator.ingest(full(time: 51, observedAt: 51), at: thresholdAt)
        XCTAssertFalse(failed.committedAny)
        XCTAssertTrue(failed.hasFailure)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        let retried = try coordinator.ingest(full(time: 51, observedAt: 52), at: retryAt)
        XCTAssertTrue(retried.committedAny)
        XCTAssertFalse(retried.hasFailure)
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == "song-a" }
        )
        XCTAssertEqual(record.actualListeningAt, thresholdAt)
    }

    func testFailedPersistenceDoesNotBlockNextSongAndBothRetryWithoutReplay() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let coordinator = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard self.persistenceAvailable else {
                    throw EvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )

        XCTAssertFalse(try coordinator.ingest(full(songID: "song-a", time: 0, observedAt: 0)).committedAny)
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-a", time: 51, observedAt: 51)).hasFailure)
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-b", time: 0, observedAt: 52)).hasFailure)
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 103)).hasFailure)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true

        let recovered = try coordinator.ingest(
            full(songID: "song-b", time: 51, observedAt: 104, isPlaying: false)
        )
        XCTAssertEqual(recovered.committedSongIDs, ["song-a", "song-b"])
        XCTAssertFalse(recovered.hasFailure)

        let noOp = try coordinator.ingest(
            full(songID: "song-b", time: 51, observedAt: 105, isPlaying: false)
        )
        XCTAssertFalse(noOp.committedAny)
        XCTAssertFalse(noOp.hasFailure)

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(
            Set(records.compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a", "song-b"]
        )
    }

    func testBatchDrainStopsAtFailureAndDoesNotRetryCommittedItems() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        var attempts: [String] = []
        let coordinator = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                attempts.append(songID)
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard self.persistenceAvailable, self.failSongID != songID else {
                    throw EvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )

        _ = try coordinator.ingest(full(songID: "song-a", time: 0, observedAt: 0))
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-a", time: 51, observedAt: 51)).hasFailure)
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-b", time: 0, observedAt: 52)).hasFailure)
        XCTAssertTrue(try coordinator.ingest(full(songID: "song-b", time: 51, observedAt: 103)).hasFailure)

        persistenceAvailable = true
        failSongID = "song-b"
        attempts.removeAll()

        let partial = try coordinator.ingest(
            full(songID: "song-b", time: 51, observedAt: 104, isPlaying: false)
        )
        XCTAssertEqual(partial.committedSongIDs, ["song-a"])
        XCTAssertTrue(partial.hasFailure)
        XCTAssertEqual(attempts, ["song-a", "song-b"])
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a"]
        )

        failSongID = nil
        attempts.removeAll()
        let remaining = try coordinator.flushPending()
        XCTAssertEqual(remaining.committedSongIDs, ["song-b"])
        XCTAssertFalse(remaining.hasFailure)
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

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: actualAt).committedAny)
        XCTAssertTrue(try coordinator.ingest(full(time: 51, observedAt: 51), at: actualAt).committedAny)

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
