import Foundation

struct ArtistIdentityResolution: Sendable {
    let candidates: [RecognizedArtist]
    let automaticMatch: RecognizedArtist?
}

struct ArtistIdentityMatcher: Sendable {
    let search: any ArtistSearchServicing

    /// A single policy for every automatic-link entry point. Candidates can still be
    /// displayed for manual selection when an alternate spelling fails or IDs conflict.
    func resolve(for name: String, including knownCandidates: [RecognizedArtist] = []) async throws -> ArtistIdentityResolution {
        let queries = ArtistNameMatching.searchQueries(for: name)
        var all = knownCandidates
        var resultsByQuery: [String: Set<String>] = [:]
        var firstFailure: Error?
        var incomplete = false
        var completed = 0

        for query in queries {
            try Task.checkCancellation()
            do {
                let found = try await search.searchArtists(query: query, exactMatchRequired: true)
                try Task.checkCancellation()
                all.append(contentsOf: found)
                resultsByQuery[ArtistNameMatching.normalized(query), default: []].formUnion(found.map(\.id))
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
                ArtistNameMatching.uniqueConfidentMatch(for: name, among: all, resultsByQuery: resultsByQuery)
        )
    }

    /// Resolve identities; callers adopt `canonicalName` as the Apple Music display name.
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

extension ArtistIdentityMatcher {
    /// Unmatched slots reuse an identity already confirmed elsewhere under the same name,
    /// as long as that name points to exactly one Apple Music artist.
    static func reusableMatches(for slots: [ArtistSlot], saved: [ArtistSlot]) -> [Int: RecognizedArtist] {
        let unresolved = slots.enumerated().filter {
            $0.element.appleMusicArtistID == nil
                && AppleMusicArtistIdentity.artistID(from: $0.element.appleMusicURL) == nil
        }
        guard !unresolved.isEmpty else { return [:] }

        var knownByName: [String: [String: ArtistSlot]] = [:]
        for source in saved {
            guard let rawID = source.appleMusicArtistID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawID.isEmpty else { continue }
            let key = ArtistNameMatching.normalized(source.name)
            guard !key.isEmpty else { continue }

            var identities = knownByName[key, default: [:]]
            if var existing = identities[rawID] {
                if existing.appleMusicURL == nil { existing.appleMusicURL = source.appleMusicURL }
                if existing.avatarURL == nil { existing.avatarURL = source.avatarURL }
                identities[rawID] = existing
            } else {
                identities[rawID] = source
            }
            knownByName[key] = identities
        }

        var result: [Int: RecognizedArtist] = [:]
        for (index, slot) in unresolved {
            let key = ArtistNameMatching.normalized(slot.name)
            guard !key.isEmpty,
                  let identities = knownByName[key],
                  identities.count == 1,
                  let (artistID, source) = identities.first else { continue }

            result[index] = RecognizedArtist(
                id: artistID,
                canonicalName: source.name,
                avatarURL: source.avatarURL.flatMap(URL.init(string:)),
                appleMusicURL: source.appleMusicURL.flatMap(URL.init(string:))
            )
        }
        return result
    }
}
