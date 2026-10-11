import Foundation

struct ArtistIdentityMatcher {
    let search: any ArtistSearchServicing

    /// Resolve identities without rewriting saved display names.
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
                    var candidates: [RecognizedArtist] = []
                    var seen = Set<String>()
                    for query in ArtistNameMatching.searchQueries(for: item.query) {
                        try Task.checkCancellation()
                        do {
                            let found = try await search.searchArtists(query: query, exactMatchRequired: true)
                            try Task.checkCancellation()
                            for candidate in found where seen.insert(candidate.id).inserted { candidates.append(candidate) }
                            // The full, exact identity is sufficient without searching aliases.
                            if query == item.query,
                               let exact = ArtistNameMatching.uniqueExactMatch(for: item.query, among: candidates) {
                                return (item.indices, exact)
                            }
                        } catch {
                            try Task.checkCancellation()
                            if error is CancellationError { throw error }
                            // One failed spelling must not discard another possible identity.
                        }
                    }
                    return (item.indices, ArtistNameMatching.uniqueConfidentMatch(for: item.query, among: candidates))
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
