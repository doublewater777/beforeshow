import Foundation

struct ArtistIdentityResolution {
    let candidates: [RecognizedArtist]
    let automaticMatch: RecognizedArtist?
}

struct ArtistIdentityMatcher {
    let search: any ArtistSearchServicing

    /// A single policy for every automatic-link entry point. Candidates can still be
    /// displayed for manual selection when an alternate spelling fails or IDs conflict.
    func resolve(for name: String, including knownCandidates: [RecognizedArtist] = []) async throws -> ArtistIdentityResolution {
        let queries = ArtistNameMatching.searchQueries(for: name)
        var all = knownCandidates
        var firstFailure: Error?
        var incomplete = false
        var completed = 0

        for query in queries {
            try Task.checkCancellation()
            do {
                let found = try await search.searchArtists(query: query, exactMatchRequired: true)
                try Task.checkCancellation()
                all.append(contentsOf: found)
                completed += 1
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                incomplete = true
                if firstFailure == nil { firstFailure = error }
            }
        }

        // If every remote variant failed, surface the error so manual search
        // can offer recovery rather than presenting a misleading empty result.
        if !queries.isEmpty && completed == 0, let firstFailure {
            throw firstFailure
        }

        var candidates: [RecognizedArtist] = []
        var seen = Set<String>()
        for artist in all where seen.insert(artist.id).inserted {
            candidates.append(artist)
        }
        return ArtistIdentityResolution(
            candidates: candidates,
            automaticMatch: incomplete ? nil :
                ArtistNameMatching.uniqueConfidentMatch(for: name, among: all)
        )
    }

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
                    do {
                        let resolution = try await resolve(for: item.query)
                        return (item.indices, resolution.automaticMatch)
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
