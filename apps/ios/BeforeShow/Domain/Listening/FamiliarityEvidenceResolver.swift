import Foundation

struct FamiliarityEvidenceResolver {
    static func isFamiliar(
        songID: String,
        records: [SongFamiliarityRecord],
        setlistMemories: [ShowSetlistMemory]
    ) -> Bool {
        records.contains {
            $0.songID == songID && ($0.manualConfirmedAt != nil || $0.actualListeningAt != nil)
        } || setlistMemories.contains { $0.catalogSongID == songID }
    }

    static func familiarSongIDs(
        records: [SongFamiliarityRecord],
        setlistMemories: [ShowSetlistMemory]
    ) -> Set<String> {
        var result = Set(
            records.compactMap { record in
                record.manualConfirmedAt != nil || record.actualListeningAt != nil
                    ? record.songID
                    : nil
            }
        )
        result.formUnion(setlistMemories.compactMap(\.catalogSongID))
        return result
    }

    static func familiarSince(
        songID: String,
        records: [SongFamiliarityRecord],
        setlistMemories: [ShowSetlistMemory]
    ) -> Date? {
        var dates: [Date] = []
        if let record = records.first(where: { $0.songID == songID }) {
            if let manual = record.manualConfirmedAt { dates.append(manual) }
            if let actual = record.actualListeningAt { dates.append(actual) }
        }
        dates.append(contentsOf: setlistMemories.compactMap { memory in
            memory.catalogSongID == songID ? memory.createdAt : nil
        })
        return dates.min()
    }
}
