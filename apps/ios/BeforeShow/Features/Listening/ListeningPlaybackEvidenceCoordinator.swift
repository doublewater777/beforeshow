import Foundation
import SwiftData

@MainActor
final class ListeningPlaybackEvidenceCoordinator {
    private let modelContext: ModelContext
    private let persistActualFamiliarity: (String, Date) throws -> Void
    private var tracker: ListeningPlaybackEvidenceTracker

    init(
        modelContext: ModelContext,
        persistActualFamiliarity: ((String, Date) throws -> Void)? = nil
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
    func ingest(_ sample: ListeningPlaybackSample, at date: Date = Date()) throws -> Bool {
        guard case let .becameFamiliar(songID) = tracker.ingest(sample) else {
            return false
        }
        do {
            try persistActualFamiliarity(songID, date)
            tracker.commitFamiliarity(songID: songID)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func breakContinuity() {
        tracker.breakContinuity()
    }
}
