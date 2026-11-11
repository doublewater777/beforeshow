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
    /// The whole feed is drawn up front so swiping back returns to the same albums; the album being previewed opens it.
    static func feed(first: ListeningDisc?, drawn: [ListeningDisc]) -> [ListeningDisc] {
        guard let first, let index = drawn.firstIndex(where: { $0.id == first.id }) else { return drawn }
        var order = drawn
        order.insert(order.remove(at: index), at: 0)
        return order
    }

    /// The record already playing stays reachable one page above the opening album,
    /// so browsing never loses what the user was listening to.
    static func keeping(_ playing: ListeningDisc?, above order: [ListeningDisc]) -> [ListeningDisc] {
        guard let playing, order.first?.id != playing.id else { return order }
        return [playing] + order.filter { $0.id != playing.id }
    }

    /// On a shelf the opening albums sit wherever the draw puts them: `slot` other albums come before them.
    static func placed(_ order: [ListeningDisc], leading count: Int, at slot: Int) -> [ListeningDisc] {
        let rest = order.dropFirst(count)
        let split = rest.startIndex + min(max(slot, 0), rest.count)
        return Array(rest[..<split]) + order.prefix(count) + rest[split...]
    }
}

/// The carousel goes round for ever: any point on its row is an album, the first coming after the last.
enum ListeningPickLoop {
    /// The row position folded into one lap, from half an album before the first to half after the last.
    static func wrapped(_ position: Double, count: Int) -> Double {
        let lap = Double(max(count, 1))
        return position - lap * ((position + 0.5) / lap).rounded(.down)
    }

    static func index(at position: Double, count: Int) -> Int {
        min(Int((wrapped(position, count: count) + 0.5).rounded(.down)), max(count - 1, 0))
    }

    /// How far to turn on to reach `target`, always forward.
    static func turn(from position: Double, to target: Int, count: Int) -> Double {
        let lap = Double(max(count, 1))
        let ahead = (Double(target) - position).truncatingRemainder(dividingBy: lap)
        return ahead < 0 ? ahead + lap : ahead
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
