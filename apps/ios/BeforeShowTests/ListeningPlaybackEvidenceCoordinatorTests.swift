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

        XCTAssertFalse(try coordinator.ingest(full(time: 0, observedAt: 0), at: heardAt).committedAny)
        XCTAssertFalse(try coordinator.ingest(full(time: 25, observedAt: 25), at: heardAt).committedAny)
        XCTAssertTrue(try coordinator.ingest(full(time: 51, observedAt: 51), at: heardAt).committedAny)
        XCTAssertFalse(try coordinator.ingest(full(time: 75, observedAt: 75), at: heardAt).committedAny)

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

    func testRetryAfterOpeningReconcilesTierAgainstCatalogSnapshotUsedAtOriginalResolution() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let opening = Date(timeIntervalSince1970: 10_000)
        let thresholdAt = opening.addingTimeInterval(-10)
        let lifecycleAt = opening.addingTimeInterval(1)
        let postOpeningAt = opening.addingTimeInterval(10)
        let v1FetchedAt = opening.addingTimeInterval(-100)
        let v1SongIDs = ["song-a", "song-b", "song-c", "song-d"]
        let show = try Show(
            name: "Opening",
            date: opening,
            startTime: opening,
            artists: [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        )
        context.insert(show)
        context.insert(ArtistCatalogSnapshot(
            artistID: "artist",
            artistName: "Artist",
            orderedSongIDs: v1SongIDs,
            fetchedAt: v1FetchedAt
        ))
        try context.save()

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

        _ = try coordinator.ingest(
            full(songID: "song-a", time: 0, observedAt: 0),
            at: thresholdAt.addingTimeInterval(-51)
        )
        let failed = try coordinator.ingest(
            full(songID: "song-a", time: 51, observedAt: 51),
            at: thresholdAt
        )
        XCTAssertTrue(failed.hasFailure)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context, now: lifecycleAt)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context, now: lifecycleAt)

        let frozenBeforeRetry = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
                .first { $0.showID == show.id }
        )
        XCTAssertTrue(frozenBeforeRetry.familiarSongIDsAtCapture.isEmpty)
        let originalTier = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShowOpeningArtistTier>())
                .first { $0.showID == show.id }
        )
        XCTAssertEqual(originalTier.tierRawValue, ListeningFamiliarityTier.firstEncounter.rawValue)
        XCTAssertEqual(originalTier.catalogSnapshotFetchedAt, v1FetchedAt)
        XCTAssertEqual(originalTier.catalogSongIDsAtResolution, v1SongIDs)

        _ = try ListeningRepository(modelContext: context).upsertArtistCatalogSnapshot(
            artistID: "artist",
            artistName: "Artist",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: [
                "song-a", "song-b", "song-c", "song-d",
                "song-e", "song-f", "song-g", "song-h"
            ],
            topSongIDs: [],
            albumIDs: [],
            fetchedAt: opening.addingTimeInterval(5)
        )
        try context.save()

        let refreshedSnapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "artist" }
        )
        XCTAssertEqual(refreshedSnapshot.orderedSongIDs.count, 8)
        XCTAssertNotEqual(refreshedSnapshot.fetchedAt, originalTier.catalogSnapshotFetchedAt)

        persistenceAvailable = true
        let recovered = try coordinator.flushPending()
        XCTAssertEqual(recovered.committedSongIDs, ["song-a"])
        XCTAssertFalse(recovered.hasFailure)

        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == "song-a" }
        )
        XCTAssertEqual(record.actualListeningAt, thresholdAt)

        let reconciledBaseline = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
                .first { $0.showID == show.id }
        )
        XCTAssertEqual(reconciledBaseline.familiarSongIDsAtCapture, ["song-a"])
        let reconciledTier = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShowOpeningArtistTier>())
                .first { $0.showID == show.id }
        )
        XCTAssertEqual(
            reconciledTier.tierRawValue,
            ListeningFamiliarityTier.gettingIntoIt.rawValue,
            "late pre-opening evidence must use V1's 1/4 denominator, not refreshed V2's 1/8"
        )
        XCTAssertEqual(reconciledTier.catalogSnapshotFetchedAt, v1FetchedAt)
        XCTAssertEqual(reconciledTier.catalogSongIDsAtResolution, v1SongIDs)

        _ = try ListeningRepository(modelContext: context)
            .confirmActualFamiliarity(songID: "song-b", at: postOpeningAt)
        try context.save()

        XCTAssertEqual(
            reconciledBaseline.familiarSongIDsAtCapture,
            ["song-a"],
            "post-opening evidence must not be mixed into the frozen opening baseline"
        )
        XCTAssertEqual(
            reconciledTier.tierRawValue,
            ListeningFamiliarityTier.gettingIntoIt.rawValue
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
