import Foundation

struct ListeningArtistAutoMatcher {
    let search: any ArtistSearchServicing

    /// Resolve identities without changing the show's names or asking users to connect each artist.
    func matches(for slots: [ArtistSlot]) async throws -> [Int: RecognizedArtist] {
        var result: [Int: RecognizedArtist] = [:]
        for (index, slot) in slots.enumerated() where slot.appleMusicArtistID == nil {
            try Task.checkCancellation()
            if let id = AppleMusicArtistIdentity.artistID(from: slot.appleMusicURL) {
                result[index] = RecognizedArtist(id: id, canonicalName: slot.name,
                                                avatarURL: slot.avatarURL.flatMap(URL.init(string:)),
                                                appleMusicURL: slot.appleMusicURL.flatMap(URL.init(string:)))
                continue
            }
            let candidates = try await search.searchArtists(query: slot.name)
            try Task.checkCancellation()
            let exact = candidates.filter { Self.normalized($0.canonicalName) == Self.normalized(slot.name) }
            let identities = Set(exact.map(\.id))
            // Same-name collisions remain unresolved instead of silently attaching the wrong catalog.
            if identities.count == 1 { result[index] = exact.first }
        }
        return result
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }
}
