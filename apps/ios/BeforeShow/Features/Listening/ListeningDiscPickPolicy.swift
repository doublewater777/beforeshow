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

enum ListeningDiscPickFilter: String, CaseIterable {
    case all, albums, singlesAndEPs

    var title: String {
        switch self {
        case .all: BSLocalization.text("全部")
        case .albums: ListeningCopy.text("专辑")
        case .singlesAndEPs: ListeningCopy.text("单曲和 EP")
        }
    }

    func includes(_ disc: ListeningDisc) -> Bool {
        guard self != .all else { return true }
        guard disc.origin == .album else { return false }
        // Apple Music's own markers: isSingle, and the " - EP" / " - Single" its catalog puts in titles
        // (isSingle alone misses multi-track singles such as "Baby Gotta Go - Single").
        let isShortRelease = disc.isSingle == true || disc.title.range(
            of: #"\s[-–—]\s*(EP|Single)\s*$"#, options: [.regularExpression, .caseInsensitive]
        ) != nil
        return self == .singlesAndEPs ? isShortRelease : !isShortRelease
    }
}

/// On-demand disc pick from the current Listening browse scope.
/// Random draws avoid recent sleeves without changing daily featured heads or reminder queues.
enum ListeningDiscPickPolicy {
    private struct Selection: Codable {
        var recentIDs: [String]
    }

    private static let keyPrefix = "listening.discPick."
    private static let recentLimit = 3

    /// The pick feed draws across the whole show; draws persist under this key.
    static let showScopeKey = "all"

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
        lineupNames: [String] = [],
        defaults: UserDefaults = .standard
    ) -> ListeningDisc? {
        var generator = SystemRandomNumberGenerator()
        return pick(showID: showID, scopeKey: scopeKey, candidates: candidates,
                    lineupNames: lineupNames, defaults: defaults, using: &generator)
    }

    static func pick<R: RandomNumberGenerator>(
        showID: UUID,
        scopeKey: String,
        candidates: [ListeningDisc],
        lineupNames: [String] = [],
        defaults: UserDefaults = .standard,
        using generator: inout R
    ) -> ListeningDisc? {
        let pool = candidatePool(from: candidates)
        guard !pool.isEmpty else { return nil }

        let lastDraw = load(key: storageKey(showID: showID, scopeKey: scopeKey), defaults: defaults).recentIDs.last

        // Prioritize releases where the show's artist is the lead artist over guest collaborations.
        let lineup = ListeningDisc.normalizedLineup(lineupNames)
        let leads = pool.filter { $0.isLeadArtist(normalizedLineup: lineup) }
        let activePool = leads.isEmpty ? pool : leads

        let withoutLastDraw = activePool.filter { $0.id != lastDraw }
        return (withoutLastDraw.isEmpty ? activePool : withoutLastDraw).randomElement(using: &generator)
    }

    /// The whole pick feed at once, as drawing `pick` until nothing is left would give it: lead releases first, then
    /// the rest, each shuffled with the last draw held back to the end of its group. Discs with nothing to play follow.
    static func order(
        showID: UUID,
        scopeKey: String,
        candidates: [ListeningDisc],
        lineupNames: [String] = [],
        defaults: UserDefaults = .standard
    ) -> [ListeningDisc] {
        var generator = SystemRandomNumberGenerator()
        return order(showID: showID, scopeKey: scopeKey, candidates: candidates,
                     lineupNames: lineupNames, defaults: defaults, using: &generator)
    }

    static func order<R: RandomNumberGenerator>(
        showID: UUID,
        scopeKey: String,
        candidates: [ListeningDisc],
        lineupNames: [String] = [],
        defaults: UserDefaults = .standard,
        using generator: inout R
    ) -> [ListeningDisc] {
        let pool = candidatePool(from: candidates)
        let lastDraw = load(key: storageKey(showID: showID, scopeKey: scopeKey), defaults: defaults).recentIDs.last
        let lineup = ListeningDisc.normalizedLineup(lineupNames)
        let isLead = pool.map { $0.isLeadArtist(normalizedLineup: lineup) }

        func shuffled(_ group: [ListeningDisc]) -> [ListeningDisc] {
            var group = group.shuffled(using: &generator)
            if let index = group.firstIndex(where: { $0.id == lastDraw }) { group.append(group.remove(at: index)) }
            return group
        }
        let drawn = shuffled(zip(pool, isLead).filter(\.1).map(\.0)) + shuffled(zip(pool, isLead).filter { !$0.1 }.map(\.0))
        var seen = Set(drawn.map(\.id))
        return drawn + candidates.filter { seen.insert($0.id).inserted }
    }

    private static func candidatePool(from candidates: [ListeningDisc]) -> [ListeningDisc] {
        var seen = Set<String>()
        return candidates.filter { disc in
            guard !disc.tracks.isEmpty, !seen.contains(disc.id) else { return false }
            seen.insert(disc.id)
            return true
        }
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
