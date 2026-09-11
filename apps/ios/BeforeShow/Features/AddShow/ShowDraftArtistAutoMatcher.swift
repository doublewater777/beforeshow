import Foundation

/// Best-effort identity enrichment for lineup names imported from links/OCR.
/// Only one normalized exact identity is accepted; same-name collisions stay
/// unresolved so the user can confirm them manually.
struct ShowDraftArtistAutoMatcher {
    let search: any ArtistSearchServicing

    func matches(for slots: [ArtistSlot]) async -> [Int: RecognizedArtist] {
        var result: [Int: RecognizedArtist] = [:]
        for (index, slot) in slots.enumerated() where slot.appleMusicArtistID == nil {
            guard !Task.isCancelled else { return result }
            let query = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            let candidates = (try? await search.searchArtists(query: query)) ?? []
            guard !Task.isCancelled else { return result }
            if let match = Self.uniqueExactMatch(for: query, among: candidates) {
                result[index] = match
            }
        }
        return result
    }

    static func uniqueExactMatch(
        for query: String,
        among candidates: [RecognizedArtist]
    ) -> RecognizedArtist? {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }
        let exact = candidates.filter { normalized($0.canonicalName) == normalizedQuery }
        let identities = Set(exact.map(\.id))
        guard identities.count == 1 else { return nil }
        return exact.first
    }

    static func normalized(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { $0.isWhitespace || $0.isNewline }
        .joined(separator: " ")
    }
}

// Keep the policy spelling used by the regression suite and older call sites.
typealias ShowDraftArtistAutoMatchPolicy = ShowDraftArtistAutoMatcher
