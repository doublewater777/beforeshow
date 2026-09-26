import Foundation

struct ListeningArtistAutoMatcher {
    let search: any ArtistSearchServicing

    /// Resolve identities without changing the show's names or asking users to connect each artist.
    func matches(for slots: [ArtistSlot]) async throws -> [Int: RecognizedArtist] {
        var result: [Int: RecognizedArtist] = [:]
        var pending: [(Int, String)] = []
        for (index, slot) in slots.enumerated() where slot.appleMusicArtistID == nil {
            try Task.checkCancellation()
            if let id = AppleMusicArtistIdentity.artistID(from: slot.appleMusicURL) {
                result[index] = RecognizedArtist(id: id, canonicalName: slot.name,
                                                avatarURL: slot.avatarURL.flatMap(URL.init(string:)),
                                                appleMusicURL: slot.appleMusicURL.flatMap(URL.init(string:)))
                continue
            }
            pending.append((index, slot.name))
        }
        try await withThrowingTaskGroup(of: (Int, RecognizedArtist?).self) { group in
            var remaining = pending.makeIterator()
            func enqueue(_ item: (Int, String)) {
                group.addTask {
                    try Task.checkCancellation()
                    let candidates = try await search.searchArtists(query: item.1)
                    try Task.checkCancellation()
                    let exact = candidates.filter { Self.normalized($0.canonicalName) == Self.normalized(item.1) }
                    // Same-name collisions must never attach the wrong catalog.
                    return (item.0, Set(exact.map(\.id)).count == 1 ? exact.first : nil)
                }
            }
            for _ in 0..<4 {
                if let item = remaining.next() { enqueue(item) }
            }
            while let (index, candidate) = try await group.next() {
                try Task.checkCancellation()
                result[index] = candidate
                if let item = remaining.next() { enqueue(item) }
            }
        }
        return result
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }
}
