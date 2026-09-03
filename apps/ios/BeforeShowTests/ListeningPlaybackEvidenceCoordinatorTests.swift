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
        XCTAssertTrue(try coordinator.ingest(full(time: 50, observedAt: 50), at: heardAt))
        XCTAssertFalse(try coordinator.ingest(full(time: 75, observedAt: 75), at: heardAt))

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.songID, "song-a")
        XCTAssertEqual(records.first?.actualListeningAt, heardAt)
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
        XCTAssertTrue(try coordinator.ingest(full(time: 50, observedAt: 50), at: actualAt))

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
