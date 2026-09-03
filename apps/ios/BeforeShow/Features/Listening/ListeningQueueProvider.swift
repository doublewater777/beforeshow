import Foundation
import SwiftData

@MainActor
struct ListeningQueueProvider {
    let modelContext: ModelContext

    func queue(
        showID: UUID,
        onlyArtistID: String? = nil
    ) throws -> [ListeningQueueEntry] {
        guard let show = try modelContext.fetch(FetchDescriptor<Show>())
            .first(where: { $0.id == showID }) else {
            return []
        }

        let snapshots = try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        let snapshotByArtistID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.artistID, $0) })
        let familiarityRecords = try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let setlistMemories = try modelContext.fetch(FetchDescriptor<ShowSetlistMemory>())
        let preferences = try modelContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        let familiarSongIDs = FamiliarityEvidenceResolver.familiarSongIDs(
            records: familiarityRecords,
            setlistMemories: setlistMemories
        )
        let excludedArtistIDs = Set(preferences.compactMap { preference in
            preference.showID == showID && preference.isExcluded ? preference.artistID : nil
        })

        let artists = show.artists.compactMap { slot -> ListeningQueueArtistInput? in
            guard let artistID = slot.appleMusicArtistID,
                  let snapshot = snapshotByArtistID[artistID] else {
                return nil
            }
            return ListeningQueueArtistInput(
                artistID: artistID,
                orderedSongIDs: snapshot.orderedSongIDs
            )
        }

        return ListeningQueueBuilder.build(
            artists: artists,
            familiarSongIDs: familiarSongIDs,
            excludedArtistIDs: excludedArtistIDs,
            onlyArtistID: onlyArtistID
        )
    }
}
