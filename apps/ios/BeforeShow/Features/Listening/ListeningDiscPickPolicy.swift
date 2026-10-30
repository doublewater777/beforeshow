import Foundation

/// Assembles the cabinet pool for 「帮我挑一张」 from the current browse scope.
enum ListeningDiscPickCandidates {
    static func discs(in groups: [ListeningRackGroup], scope: ListeningBrowseState.Scope) -> [ListeningDisc] {
        switch scope {
        case .all:
            return groups.flatMap { group -> [ListeningDisc] in
                switch group.kind {
                case .live:
                    return group.discs
                case .artist(_, _, let isConnected):
                    return isConnected ? group.discs : []
                }
            }
        case let .artist(id):
            return groups.first(where: { $0.scope == .artist(id) })?.discs ?? []
        }
    }
}

/// On-demand disc pick from the current Listening browse scope.
/// Prefers unexplored sleeves; never changes daily featured heads or reminder queues.
enum ListeningDiscPickPolicy {
    private struct Selection: Codable {
        var recentIDs: [String]
    }

    private static let keyPrefix = "listening.discPick."
    private static let recentLimit = 3

    static func scopeKey(for scope: ListeningBrowseState.Scope) -> String {
        switch scope {
        case .all: "all"
        case let .artist(id): id
        }
    }

    static func clearDraws(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    static func recordDraw(
        showID: UUID,
        scopeKey: String,
        discID: String,
        defaults: UserDefaults = .standard
    ) {
        let key = storageKey(showID: showID, scopeKey: scopeKey)
        var recent = load(key: key, defaults: defaults).recentIDs.filter { $0 != discID }
        recent.append(discID)
        save(Selection(recentIDs: Array(recent.suffix(recentLimit))), key: key, defaults: defaults)
    }

    static func pick(
        showID: UUID,
        scopeKey: String,
        candidates: [ListeningDisc],
        familiarSongIDs: Set<String>,
        topSongIDs: [String] = [],
        excluding excludedIDs: Set<String> = [],
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> ListeningDisc? {
        let pool = prioritizedPool(from: candidates)
        guard !pool.isEmpty else { return nil }

        let key = storageKey(showID: showID, scopeKey: scopeKey)
        let recentIDs = load(key: key, defaults: defaults).recentIDs
        let blocked = excludedIDs.union(recentIDs)
        let fresh = pool.filter { !blocked.contains($0.id) }
        let unexcluded = pool.filter { !excludedIDs.contains($0.id) }
        let available: [ListeningDisc]
        if !fresh.isEmpty {
            available = fresh
        } else if !unexcluded.isEmpty {
            available = unexcluded
        } else {
            available = pool
        }

        var topRanks: [String: Int] = [:]
        for (index, id) in topSongIDs.prefix(10).enumerated() where topRanks[id] == nil {
            topRanks[id] = 10 - index
        }

        let nonce = UInt64(recentIDs.count)
        return available.max(by: {
            let left = score($0, familiarSongIDs: familiarSongIDs, topRanks: topRanks, now: now)
            let right = score($1, familiarSongIDs: familiarSongIDs, topRanks: topRanks, now: now)
            if left == right {
                return tieBreak($0, scopeKey: scopeKey, nonce: nonce)
                    < tieBreak($1, scopeKey: scopeKey, nonce: nonce)
            }
            return left < right
        })
    }

    private static func prioritizedPool(from candidates: [ListeningDisc]) -> [ListeningDisc] {
        var seen = Set<String>()
        return candidates.filter { disc in
            guard !disc.tracks.isEmpty, !seen.contains(disc.id) else { return false }
            seen.insert(disc.id)
            return true
        }
    }

    private static func score(
        _ disc: ListeningDisc,
        familiarSongIDs: Set<String>,
        topRanks: [String: Int],
        now: Date
    ) -> Double {
        let tracks = Set(disc.tracks.map(\.id))
        let popular = min(40, tracks.reduce(0) { $0 + (topRanks[$1] ?? 0) * 2 })
        let unexplored = Double(tracks.filter { !familiarSongIDs.contains($0) }.count)
            / Double(max(tracks.count, 1))
        let recentRelease = disc.releaseDate.map {
            now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 366 * 86_400
        } == true
        return Double(popular) + unexplored * 6 + (recentRelease ? 1.5 : 0)
    }

    /// Unlike Hasher, FNV-1a is stable across app launches.
    private static func tieBreak(_ disc: ListeningDisc, scopeKey: String, nonce: UInt64) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(scopeKey)|\(nonce)|\(disc.id)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func storageKey(showID: UUID, scopeKey: String) -> String {
        "\(keyPrefix)\(showID.uuidString).\(scopeKey)"
    }

    private static func load(key: String, defaults: UserDefaults) -> Selection {
        defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Selection.self, from: $0) }
            ?? Selection(recentIDs: [])
    }

    private static func save(_ selection: Selection, key: String, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: key)
        }
    }
}
