import Foundation

/// Poster tiers follow lineup order: organizers list headliners first, so no timetable is needed.
struct ListeningPosterTiers<Item> {
    static var headlinerCount: Int { 2 }
    static var secondCount: Int { 3 }
    static var restLimit: Int { 6 }

    let headliners: [Item]
    let second: [Item]
    let rest: [Item]
    /// More artists than the poster shows; the full lineup lives behind a link.
    let hasMore: Bool

    init(_ items: [Item]) {
        headliners = Array(items.prefix(Self.headlinerCount))
        second = Array(items.dropFirst(Self.headlinerCount).prefix(Self.secondCount))
        let remaining = Array(items.dropFirst(Self.headlinerCount + Self.secondCount))
        rest = Array(remaining.prefix(Self.restLimit))
        hasMore = remaining.count > Self.restLimit
    }
}

enum ListeningReleaseKind: CaseIterable {
    case album, ep, single
}

enum ListeningArtistReleases {
    private static let suffix = #"\s[-–—]\s*(EP|Single)\s*$"#

    static func kind(_ disc: ListeningDisc) -> ListeningReleaseKind {
        if let range = disc.title.range(of: suffix, options: [.regularExpression, .caseInsensitive]) {
            return disc.title[range].localizedCaseInsensitiveContains("EP") ? .ep : .single
        }
        return disc.isSingle == true ? .single : .album
    }

    /// The catalog suffix only repeats what the shelf heading already says.
    static func displayTitle(_ disc: ListeningDisc) -> String {
        disc.title.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// Lead with the newest album; an EP, then a single, only when there is nothing bigger.
    static func featured(_ newestFirst: [ListeningDisc]) -> ListeningDisc? {
        for kind in ListeningReleaseKind.allCases {
            if let disc = newestFirst.first(where: { self.kind($0) == kind }) { return disc }
        }
        return nil
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
}

struct ListeningLineupSection: Identifiable {
    let id: String
    let artists: [ListeningBrowseArtist]

    static func sections(_ artists: [ListeningBrowseArtist], query: String = "") -> [ListeningLineupSection] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matching = needle.isEmpty ? artists : artists.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        let grouped = Dictionary(grouping: matching, by: indexLetter)
        return grouped.keys.sorted { lhs, rhs in
            lhs == "#" ? false : rhs == "#" ? true : lhs < rhs
        }.map { key in
            ListeningLineupSection(id: key, artists: grouped[key, default: []].sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        }
    }

    static func indexLetter(_ artist: ListeningBrowseArtist) -> String {
        let latin = artist.name.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? artist.name
        guard let first = latin.trimmingCharacters(in: .whitespaces).first?.uppercased(),
              first.range(of: "^[A-Z]$", options: .regularExpression) != nil else { return "#" }
        return first
    }
}
