import Foundation

/// Poster tiers follow lineup order: organizers list headliners first, so no timetable is needed.
struct ListeningPosterTiers<Item> {
    static var headlinerCount: Int { 2 }
    static var secondCount: Int { 3 }
    static var restLimit: Int { 6 }

    let headliners: [Item]
    let second: [Item]
    let rest: [Item]
    /// More artists than the folded poster shows; expanding sets them all in the last tier.
    let hasMore: Bool

    init(_ items: [Item], expanded: Bool = false) {
        headliners = Array(items.prefix(Self.headlinerCount))
        second = Array(items.dropFirst(Self.headlinerCount).prefix(Self.secondCount))
        let remaining = Array(items.dropFirst(Self.headlinerCount + Self.secondCount))
        rest = expanded ? remaining : Array(remaining.prefix(Self.restLimit))
        hasMore = remaining.count > Self.restLimit
    }
}

enum ListeningArtistReleases {
    /// Lead with the newest album; the newest single or EP only when there is no album.
    static func featured(_ newestFirst: [ListeningDisc]) -> ListeningDisc? {
        newestFirst.first(where: ListeningDiscPickFilter.albums.includes) ?? newestFirst.first
    }

    /// Albums, singles and EPs newest first; featured playlists stay out. The catalog
    /// often lists one release twice (say a 1-track and a 3-track single); the fuller one stays.
    static func newestFirst(_ discs: [ListeningDisc]) -> [ListeningDisc] {
        var fullest: [String: ListeningDisc] = [:]
        for disc in discs where disc.origin == .album {
            let key = disc.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if (fullest[key]?.tracks.count ?? -1) < disc.tracks.count { fullest[key] = disc }
        }
        let kept = Set(fullest.values.map(\.id))
        return discs.filter { kept.contains($0.id) }.enumerated().sorted { lhs, rhs in
            switch (lhs.element.releaseDate, rhs.element.releaseDate) {
            case let (a?, b?) where a != b: a > b
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

enum ListeningPickOrder {
    /// The whole feed is drawn up front so swiping back returns to the same albums.
    /// Each draw only sees albums not yet in the feed, so every candidate appears exactly once.
    static func feed(first: ListeningDisc?, candidates: [ListeningDisc], draw: ([ListeningDisc]) -> ListeningDisc?) -> [ListeningDisc] {
        var order: [ListeningDisc] = []
        var seen = Set<String>()
        var remaining = candidates.filter { seen.insert($0.id).inserted }
        seen.removeAll()
        if let first, let index = remaining.firstIndex(where: { $0.id == first.id }) {
            order.append(remaining.remove(at: index))
        }
        while !remaining.isEmpty {
            let pick = draw(remaining).flatMap { next in remaining.firstIndex { $0.id == next.id } } ?? 0
            order.append(remaining.remove(at: pick))
        }
        return order
    }

    /// The record already playing stays reachable one page above the opening album,
    /// so browsing never loses what the user was listening to.
    static func keeping(_ playing: ListeningDisc?, above order: [ListeningDisc]) -> [ListeningDisc] {
        guard let playing, order.first?.id != playing.id else { return order }
        return [playing] + order.filter { $0.id != playing.id }
    }

    /// On a shelf the opening albums sit mid-row, with albums on both sides to browse.
    static func centred(_ order: [ListeningDisc], leading count: Int) -> [ListeningDisc] {
        let rest = order.dropFirst(count)
        let middle = rest.startIndex + rest.count / 2
        return Array(rest[..<middle]) + order.prefix(count) + rest[middle...]
    }
}

/// When the 「帮我挑一张」 card draws a new album. It never reshuffles on its own.
enum ListeningPickCardPolicy {
    /// An album the pool no longer offers is replaced; a playlist the user stopped on is kept.
    static func needsNewDraw(current: ListeningDisc?, candidateIDs: [String]) -> Bool {
        guard let current else { return true }
        return current.origin == .album && !candidateIDs.contains(current.id)
    }
}
