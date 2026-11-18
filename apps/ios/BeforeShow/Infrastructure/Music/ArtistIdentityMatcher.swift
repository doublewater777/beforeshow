import Foundation

/// Searches each unresolved credit once and adopts the provider's preferred
/// photographed artist. Existing identities are never overwritten.
struct ArtistIdentityMatcher: Sendable {
    let search: any ArtistSearchServicing

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
                let key = ArtistNameMatching.searchKey(query)
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
                        let candidates = try await search.searchArtists(query: item.query)
                        try Task.checkCancellation()
                        return (item.indices, ArtistNameMatching.automaticMatch(among: candidates))
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
