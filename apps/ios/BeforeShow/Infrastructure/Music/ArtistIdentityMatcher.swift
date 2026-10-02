import Foundation

struct ArtistIdentityMatcher {
    let search: any ArtistSearchServicing

    /// Resolve identities without changing the show's names or asking users to connect each artist.
    func matches(for slots: [ArtistSlot]) async throws -> [Int: RecognizedArtist] {
        var result: [Int: RecognizedArtist] = [:]
        var pending: [(indices: [Int], query: String)] = []
        var pendingByName: [String: Int] = [:]
        for (index, slot) in slots.enumerated() where slot.appleMusicArtistID == nil {
            try Task.checkCancellation()
            if let id = AppleMusicArtistIdentity.artistID(from: slot.appleMusicURL) {
                result[index] = RecognizedArtist(id: id, canonicalName: slot.name,
                                                avatarURL: slot.avatarURL.flatMap(URL.init(string:)),
                                                appleMusicURL: slot.appleMusicURL.flatMap(URL.init(string:)))
                continue
            }
            let query = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let key = ArtistNameMatching.normalized(query)
                if let existing = pendingByName[key] {
                    pending[existing].indices.append(index)
                } else {
                    pendingByName[key] = pending.count
                    pending.append(([index], query))
                }
            }
        }
        try await withThrowingTaskGroup(of: ([Int], RecognizedArtist?).self) { group in
            var remaining = pending.makeIterator()
            func enqueue(_ item: (indices: [Int], query: String)) {
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let candidates = try await search.searchArtists(query: item.query, exactMatchRequired: true)
                        try Task.checkCancellation()
                        return (item.indices, ArtistNameMatching.uniqueExactMatch(for: item.query, among: candidates))
                    } catch {
                        try Task.checkCancellation()
                        if error is CancellationError { throw error }
                        // One unavailable artist must not discard the rest of the lineup.
                        return (item.indices, nil)
                    }
                }
            }
            for _ in 0..<4 {
                if let item = remaining.next() { enqueue(item) }
            }
            while let (indices, candidate) = try await group.next() {
                try Task.checkCancellation()
                for index in indices { result[index] = candidate }
                if let item = remaining.next() { enqueue(item) }
            }
        }
        return result
    }
}
