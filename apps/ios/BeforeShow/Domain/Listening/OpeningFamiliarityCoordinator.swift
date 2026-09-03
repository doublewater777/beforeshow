import Foundation
import SwiftData

@MainActor
enum OpeningFamiliarityCoordinator {
    @discardableResult
    static func captureDueBaselines(
        in modelContext: ModelContext,
        now: Date = Date(),
        saveChanges: Bool = true
    ) throws -> Bool {
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        let baselines = try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
        let familiarityRecords = try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let setlistMemories = try modelContext.fetch(FetchDescriptor<ShowSetlistMemory>())
        var existingShowIDs = Set(baselines.map(\.showID))
        let familiarSongIDs = FamiliarityEvidenceResolver.familiarSongIDs(
            records: familiarityRecords,
            setlistMemories: setlistMemories
        ).sorted()
        let repository = ListeningRepository(modelContext: modelContext)
        var didChange = false

        for show in shows {
            guard show.wasAddedAsHistorical != true,
                  show.changeStatus != .canceled,
                  !existingShowIDs.contains(show.id) else {
                continue
            }
            let timeState = CurrentShowTimeState(show: show, now: now)
            guard let effectiveStart = timeState.effectiveStartTime,
                  now >= effectiveStart else {
                continue
            }

            _ = try repository.insertOpeningBaselineIfAbsent(
                showID: show.id,
                effectiveStart: effectiveStart,
                familiarSongIDs: familiarSongIDs,
                capturedAt: now
            )
            existingShowIDs.insert(show.id)
            didChange = true
        }

        if saveChanges, didChange {
            try modelContext.save()
        }
        return didChange
    }

    @discardableResult
    static func resolveAvailableTiers(
        in modelContext: ModelContext,
        now: Date = Date(),
        saveChanges: Bool = true
    ) throws -> Bool {
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        let baselines = try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
        let snapshots = try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        let tiers = try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>())
        let baselineByShowID = Dictionary(uniqueKeysWithValues: baselines.map { ($0.showID, $0) })
        let snapshotByArtistID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.artistID, $0) })
        var existingKeys = Set(tiers.map(\.uniqueKey))
        let repository = ListeningRepository(modelContext: modelContext)
        var didChange = false

        for show in shows {
            guard let baseline = baselineByShowID[show.id] else { continue }
            let familiarAtOpening = Set(baseline.familiarSongIDsAtCapture)

            for artist in show.artists {
                guard let artistID = artist.appleMusicArtistID,
                      !artistID.isEmpty,
                      let snapshot = snapshotByArtistID[artistID],
                      !snapshot.orderedSongIDs.isEmpty else {
                    continue
                }
                let key = ShowOpeningArtistTier.makeUniqueKey(showID: show.id, artistID: artistID)
                guard !existingKeys.contains(key) else { continue }

                let catalogSongIDs = Set(snapshot.orderedSongIDs)
                let familiarCount = familiarAtOpening.intersection(catalogSongIDs).count
                guard let tier = ListeningFamiliarityTier.resolve(
                    familiarCount: familiarCount,
                    totalCount: snapshot.orderedSongIDs.count
                ) else {
                    continue
                }

                _ = try repository.insertOpeningTierIfAbsent(
                    showID: show.id,
                    artistID: artistID,
                    artistName: artist.name,
                    tierRawValue: tier.rawValue,
                    baselineCapturedAt: baseline.capturedAt,
                    catalogSnapshotFetchedAt: snapshot.fetchedAt,
                    resolvedAt: now
                )
                existingKeys.insert(key)
                didChange = true
            }
        }

        if saveChanges, didChange {
            try modelContext.save()
        }
        return didChange
    }

    static func runLifecyclePass(
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        var didChange = try ListeningShowLifecycleCoordinator.reconcileStoredState(
            in: modelContext,
            now: now
        )
        didChange = try captureDueBaselines(
            in: modelContext,
            now: now,
            saveChanges: false
        ) || didChange
        didChange = try resolveAvailableTiers(
            in: modelContext,
            now: now,
            saveChanges: false
        ) || didChange
        if didChange {
            try modelContext.save()
        }
    }
}
