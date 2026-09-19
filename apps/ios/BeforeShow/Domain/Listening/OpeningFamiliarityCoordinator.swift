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
                  !existingShowIDs.contains(show.id),
                  let effectiveStart = ListeningShowStartPolicy.effectiveOpeningStart(show: show),
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
    static func reconcilePersistedActualFamiliarity(
        songID: String,
        familiarityReachedAt: Date,
        in modelContext: ModelContext,
        reconciledAt: Date = Date(),
        saveChanges: Bool = true
    ) throws -> Bool {
        let baselines = try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
            .filter {
                familiarityReachedAt <= $0.effectiveStartAtCapture
                    && !$0.familiarSongIDsAtCapture.contains(songID)
            }
        guard !baselines.isEmpty else { return false }

        let showsByID = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Show>())
                .map { ($0.id, $0) }
        )
        let snapshotsByArtistID = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .map { ($0.artistID, $0) }
        )
        let tiersByKey = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>())
                .map { ($0.uniqueKey, $0) }
        )
        var didChange = false

        for baseline in baselines {
            baseline.familiarSongIDsAtCapture = Array(
                Set(baseline.familiarSongIDsAtCapture).union([songID])
            ).sorted()
            didChange = true

            guard let show = showsByID[baseline.showID] else { continue }
            let familiarAtOpening = Set(baseline.familiarSongIDsAtCapture)

            for artist in show.artists {
                guard let artistID = artist.appleMusicArtistID,
                      !artistID.isEmpty,
                      let tier = tiersByKey[
                        ShowOpeningArtistTier.makeUniqueKey(
                            showID: show.id,
                            artistID: artistID
                        )
                      ] else {
                    continue
                }

                let catalogSongIDsAtResolution: [String]
                if !tier.catalogSongIDsAtResolution.isEmpty {
                    catalogSongIDsAtResolution = tier.catalogSongIDsAtResolution
                } else if let snapshot = snapshotsByArtistID[artistID],
                          snapshot.fetchedAt == tier.catalogSnapshotFetchedAt {
                    catalogSongIDsAtResolution = snapshot.orderedSongIDs
                    tier.catalogSongIDsAtResolution = snapshot.orderedSongIDs
                    didChange = true
                } else {
                    continue
                }

                guard catalogSongIDsAtResolution.contains(songID) else { continue }
                let catalogSongIDs = Set(catalogSongIDsAtResolution)
                let familiarCount = familiarAtOpening.intersection(catalogSongIDs).count
                guard let correctedTier = ListeningFamiliarityTier.resolve(
                    familiarCount: familiarCount,
                    totalCount: catalogSongIDsAtResolution.count
                ),
                tier.tierRawValue != correctedTier.rawValue else {
                    continue
                }

                tier.tierRawValue = correctedTier.rawValue
                tier.resolvedAt = reconciledAt
            }
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
                    catalogSongIDsAtResolution: snapshot.orderedSongIDs,
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
