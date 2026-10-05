import Foundation
import SwiftData

@MainActor
enum TimetableListeningSignals {
    /// Extracts artist names that have listening evidence (e.g., familiar songs,
    /// catalog snapshot, or recent listening) in a read-only manner.
    /// Strictly NEVER mutates `isInterested`.
    static func resolveListenedArtistNames(
        for show: Show?,
        in modelContext: ModelContext
    ) -> Set<String> {
        var names = Set<String>()

        // 1. Collect artists from the current show lineup that have Apple Music connection
        if let artists = show?.artists {
            for slot in artists {
                if slot.appleMusicArtistID != nil || slot.appleMusicURL != nil || slot.avatarURL != nil {
                    names.insert(slot.name)
                }
            }
        }

        // 2. Collect familiar song artists
        let descriptor = FetchDescriptor<SongFamiliarityRecord>()
        if let familiarityRecords = try? modelContext.fetch(descriptor), !familiarityRecords.isEmpty {
            let songIDs = Set(familiarityRecords.map(\.songID))
            let songDescriptor = FetchDescriptor<CatalogSong>()
            if let songs = try? modelContext.fetch(songDescriptor) {
                for song in songs where songIDs.contains(song.appleMusicSongID) {
                    names.insert(song.artistName)
                    names.formUnion(song.performerArtistNames)
                }
            }
        }

        // 3. Collect from recent listening if present
        if let showID = show?.id {
            let listeningDescriptor = FetchDescriptor<ShowRecentListening>()
            if let recent = try? modelContext.fetch(listeningDescriptor) {
                let showRecent = recent.filter { $0.showID == showID }
                if !showRecent.isEmpty {
                    let songDescriptor = FetchDescriptor<CatalogSong>()
                    let recentSongIDs = Set(showRecent.map(\.songID))
                    if let songs = try? modelContext.fetch(songDescriptor) {
                        for song in songs where recentSongIDs.contains(song.appleMusicSongID) {
                            names.insert(song.artistName)
                        }
                    }
                }
            }
        }

        return names
    }
}
