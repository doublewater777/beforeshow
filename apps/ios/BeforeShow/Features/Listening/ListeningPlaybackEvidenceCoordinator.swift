import Foundation
import SwiftData

struct ListeningPlaybackEvidenceDrainResult {
    let committedSongIDs: [String]
    let hasFailure: Bool

    var committedAny: Bool { !committedSongIDs.isEmpty }
}

@MainActor
final class ListeningPlaybackEvidenceCoordinator {
    private let modelContext: ModelContext
    private let persistActualFamiliarity: @MainActor (String, Date) throws -> Void
    private var tracker: ListeningPlaybackEvidenceTracker

    init(
        modelContext: ModelContext,
        persistActualFamiliarity: (@MainActor (String, Date) throws -> Void)? = nil
    ) throws {
        self.modelContext = modelContext
        self.persistActualFamiliarity = persistActualFamiliarity ?? { songID, date in
            _ = try ListeningRepository(modelContext: modelContext)
                .confirmActualFamiliarity(songID: songID, at: date)
            try modelContext.save()
        }
        let existingActualSongIDs = Set(
            try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>()).compactMap { record in
                record.actualListeningAt == nil ? nil : record.songID
            }
        )
        tracker = ListeningPlaybackEvidenceTracker(alreadyRecordedSongIDs: existingActualSongIDs)
    }

    @discardableResult
    func record(
        _ sample: ListeningPlaybackSample,
        at date: Date = Date()
    ) -> ListeningPlaybackEvidenceUpdate {
        tracker.ingest(sample, familiarityReachedAt: date)
    }

    @discardableResult
    func ingest(
        _ sample: ListeningPlaybackSample,
        at date: Date = Date()
    ) throws -> ListeningPlaybackEvidenceDrainResult {
        _ = record(sample, at: date)
        return drainPending()
    }

    @discardableResult
    func flushPending() throws -> ListeningPlaybackEvidenceDrainResult {
        drainPending()
    }

    func breakContinuity() {
        tracker.breakContinuity()
    }

    private func drainPending() -> ListeningPlaybackEvidenceDrainResult {
        var committedSongIDs: [String] = []
        while let pending = tracker.nextPendingFamiliarity {
            do {
                try persistActualFamiliarity(
                    pending.songID,
                    pending.familiarityReachedAt
                )
                tracker.commitFamiliarity(songID: pending.songID)
                committedSongIDs.append(pending.songID)
            } catch {
                modelContext.rollback()
                return ListeningPlaybackEvidenceDrainResult(
                    committedSongIDs: committedSongIDs,
                    hasFailure: true
                )
            }
        }
        return ListeningPlaybackEvidenceDrainResult(
            committedSongIDs: committedSongIDs,
            hasFailure: false
        )
    }
}
