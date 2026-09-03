import Foundation
import SwiftData

@MainActor
final class ListeningPlaybackEvidenceCoordinator {
    private let modelContext: ModelContext
    private var tracker: ListeningPlaybackEvidenceTracker

    init(modelContext: ModelContext) throws {
        self.modelContext = modelContext
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
        _ = try ListeningRepository(modelContext: modelContext)
            .confirmActualFamiliarity(songID: songID, at: date)
        try modelContext.save()
        return true
    }

    func breakContinuity() {
        tracker.breakContinuity()
    }
}
