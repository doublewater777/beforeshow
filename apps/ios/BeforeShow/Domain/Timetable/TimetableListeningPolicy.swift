import Foundation

enum TimetableListeningPolicy {
    /// Determines whether an artist has listening evidence from existing records.
    /// Pure function; does NOT mutate or touch `isInterested` in any way.
    static func hasListeningEvidence(
        artistName: String,
        listenedArtistNames: Set<String>
    ) -> Bool {
        let normalized = ArtistNameMatching.normalized(artistName)
        guard !normalized.isEmpty else { return false }

        for candidate in listenedArtistNames {
            let normalizedCandidate = ArtistNameMatching.normalized(candidate)
            if normalized == normalizedCandidate {
                return true
            }
        }
        return false
    }

    /// Ranks performances weakly so listened artists can be visually prioritized
    /// when weak-sort mode is active, while chronologically preserving timeslots.
    /// Strictly read-only: NEVER mutates `isInterested`.
    static func isListened(
        artistName: String,
        listenedArtistNames: Set<String>
    ) -> Bool {
        hasListeningEvidence(artistName: artistName, listenedArtistNames: listenedArtistNames)
    }
}
