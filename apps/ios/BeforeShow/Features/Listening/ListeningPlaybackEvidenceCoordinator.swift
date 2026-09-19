import Foundation
import SwiftData

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
    func ingest(_ sample: ListeningPlaybackSample, at date: Date = Date()) throws -> Bool {
        _ = tracker.ingest(sample)
        return try drainPending(at: date)
    }

    @discardableResult
    func flushPending(at date: Date = Date()) throws -> Bool {
        try drainPending(at: date)
    }

    func breakContinuity() {
        tracker.breakContinuity()
    }

    @discardableResult
    private func drainPending(at date: Date) throws -> Bool {
        var persistedAny = false
        while let songID = tracker.nextPendingFamiliaritySongID {
            do {
                try persistActualFamiliarity(songID, date)
                tracker.commitFamiliarity(songID: songID)
                persistedAny = true
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        return persistedAny
    }
}
