import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class OpeningFamiliarityMutationOrderingTests: XCTestCase {
    func testManualConfirmationCapturesBaselineBeforeNewEvidence() throws {
        let (container, context, show, now) = try makeDueShowContext()
        defer { withExtendedLifetime(container) {} }
        let repository = ListeningRepository(modelContext: context)

        _ = try repository.confirmManualFamiliarity(songID: "new-manual", at: now)

        let baseline = try baseline(for: show.id, in: context)
        XCTAssertFalse(baseline.familiarSongIDsAtCapture.contains("new-manual"))
    }

    func testActualConfirmationCapturesBaselineBeforeNewEvidence() throws {
        let (container, context, show, now) = try makeDueShowContext()
        defer { withExtendedLifetime(container) {} }
        let repository = ListeningRepository(modelContext: context)

        _ = try repository.confirmActualFamiliarity(songID: "new-actual", at: now)

        let baseline = try baseline(for: show.id, in: context)
        XCTAssertFalse(baseline.familiarSongIDsAtCapture.contains("new-actual"))
    }

    func testSetlistAddCapturesBaselineBeforeNewRecall() throws {
        let (container, context, show, now) = try makeDueShowContext()
        defer { withExtendedLifetime(container) {} }
        let repository = ListeningRepository(modelContext: context)

        _ = try repository.addSetlistMemory(
            showID: show.id,
            catalogSongID: "new-recall",
            at: now
        )

        let baseline = try baseline(for: show.id, in: context)
        XCTAssertFalse(baseline.familiarSongIDsAtCapture.contains("new-recall"))
    }

    func testManualUndoCapturesExistingEvidenceBeforeRemovingIt() throws {
        let (container, context, show, now) = try makeDueShowContext()
        defer { withExtendedLifetime(container) {} }
        context.insert(SongFamiliarityRecord(
            songID: "manual-before-opening",
            manualConfirmedAt: now.addingTimeInterval(-100)
        ))
        try context.save()
        let repository = ListeningRepository(modelContext: context)

        try repository.undoManualFamiliarity(songID: "manual-before-opening", at: now)

        let baseline = try baseline(for: show.id, in: context)
        XCTAssertTrue(baseline.familiarSongIDsAtCapture.contains("manual-before-opening"))
    }

    func testSetlistDeleteCapturesExistingRecallBeforeRemovingIt() throws {
        let (container, context, show, now) = try makeDueShowContext()
        defer { withExtendedLifetime(container) {} }
        let memory = ShowSetlistMemory(
            showID: show.id,
            catalogSongID: "recall-before-opening",
            createdAt: now.addingTimeInterval(-100)
        )
        context.insert(memory)
        try context.save()
        let repository = ListeningRepository(modelContext: context)

        try repository.deleteSetlistMemory(memory, at: now)

        let baseline = try baseline(for: show.id, in: context)
        XCTAssertTrue(baseline.familiarSongIDsAtCapture.contains("recall-before-opening"))
    }

    private func makeDueShowContext() throws -> (ModelContainer, ModelContext, Show, Date) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = now.addingTimeInterval(-60)
        let show = try Show(name: "Due", date: start, startTime: start)
        context.insert(show)
        try context.save()
        return (container, context, show, now)
    }

    private func baseline(
        for showID: UUID,
        in context: ModelContext
    ) throws -> ShowOpeningFamiliarityBaseline {
        try XCTUnwrap(
            context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
                .first(where: { $0.showID == showID })
        )
    }
}
