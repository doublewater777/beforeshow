import Foundation

/// One shelf section: the live-preview compilation or one artist. The head disc
/// stands on the first-level rack; the full list unfolds in place.
struct ListeningRackGroup: Identifiable, Equatable {
    enum Kind: Equatable {
        case live
        case artist(id: String, slotIndex: Int, isConnected: Bool)
    }

    let id: String
    let kind: Kind
    let name: String
    let artworkURL: URL?
    let discs: [ListeningDisc]
    var featuredDiscID: String? = nil
    var catalogStatus: ListeningArtistCatalogStatus?
    var hasCatalog = true

    var head: ListeningDisc? { discs.first(where: { $0.id == featuredDiscID }) ?? discs.first }
    var isConnectedArtist: Bool {
        if case .artist(_, _, true) = kind { return true }
        return false
    }
    /// Before an artist's catalog arrives the album count is unknown, so it stays expandable.
    var canExpand: Bool { discs.count > 1 || (isConnectedArtist && !hasCatalog) }
    var scope: ListeningBrowseState.Scope {
        switch kind {
        case .live: .all
        case let .artist(id, _, _): .artist(id)
        }
    }
}

enum ListeningArtistCatalogStatus: Equatable {
    case loading
    case failed
}

/// Wanted artists first, then stage order; artists missing from the timetable keep lineup order.
enum ListeningRackOrdering {
    struct Performance {
        let artistName: String
        let startsAt: Date
        let isInterested: Bool
    }

    static func order(names: [String], performances: [Performance]) -> [Int] {
        func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var byName: [String: Performance] = [:]
        for performance in performances {
            let name = key(performance.artistName)
            if let existing = byName[name], existing.startsAt <= performance.startsAt,
               existing.isInterested || !performance.isInterested { continue }
            byName[name] = performance
        }
        return names.indices.sorted { lhs, rhs in
            let a = byName[key(names[lhs])], b = byName[key(names[rhs])]
            let wantA = a?.isInterested == true, wantB = b?.isInterested == true
            if wantA != wantB { return wantA }
            switch (a?.startsAt, b?.startsAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs < rhs
            }
        }
    }
}

/// Selects a daily sleeve without reordering releases or changing the seated CD.
enum ListeningDailyFeaturedDiscPolicy {
    private struct Selection: Codable {
        let day: String
        let discID: String
        let recentIDs: [String]
    }

    static func clearSelections(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("listening.dailyFeatured.") {
            defaults.removeObject(forKey: key)
        }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static func featuredDiscID(
        showID: UUID,
        artistID: String,
        discs: [ListeningDisc],
        topSongIDs: [String],
        familiarSongIDs: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> String? {
        let key = "listening.dailyFeatured.\(showID.uuidString).\(artistID)"
        let day = dayKey(for: now, calendar: calendar)
        let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Selection.self, from: $0) }
        if let saved, saved.day == day, discs.contains(where: { $0.id == saved.discID }) {
            return saved.discID
        }

        let albums = discs.filter { $0.origin == .album && $0.isSingle != true && !$0.tracks.isEmpty }
        let singles = discs.filter { $0.origin == .album && $0.isSingle == true && !$0.tracks.isEmpty }
        let playlists = discs.filter {
            if case .featuredPlaylist = $0.origin { return !$0.tracks.isEmpty }
            return false
        }
        let pool = !albums.isEmpty ? albums : (!singles.isEmpty ? singles : playlists)
        let withArtwork = pool.filter { $0.artworkURL != nil }
        let candidates = withArtwork.isEmpty ? pool : withArtwork
        guard !candidates.isEmpty else { return nil }

        let recentIDs: [String]
        if let saved {
            recentIDs = saved.day == day
                ? saved.recentIDs
                : Array((saved.recentIDs + [saved.discID]).suffix(2))
        } else {
            recentIDs = []
        }
        let excluded = Set(recentIDs.suffix(min(2, candidates.count - 1)))
        let fresh = candidates.filter { !excluded.contains($0.id) }
        let available = fresh.isEmpty ? candidates : fresh

        var topRanks: [String: Int] = [:]
        for (index, id) in topSongIDs.prefix(10).enumerated() where topRanks[id] == nil {
            topRanks[id] = 10 - index
        }
        func score(_ disc: ListeningDisc) -> Double {
            let tracks = Set(disc.tracks.map(\.id))
            let popular = min(40, tracks.reduce(0) { $0 + (topRanks[$1] ?? 0) * 2 })
            let unexplored = Double(tracks.filter { !familiarSongIDs.contains($0) }.count)
                / Double(max(tracks.count, 1))
            let recentRelease = disc.releaseDate.map {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 366 * 86_400
            } == true
            return Double(popular) + unexplored * 6 + (recentRelease ? 1.5 : 0)
        }
        // Unlike Hasher, FNV-1a is stable across app launches.
        func tieBreak(_ disc: ListeningDisc) -> UInt64 {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in "\(artistID)|\(day)|\(disc.id)".utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            return hash
        }
        guard let featured = available.max(by: {
            let left = score($0), right = score($1)
            return left == right ? tieBreak($0) < tieBreak($1) : left < right
        }) else { return nil }
        if let data = try? JSONEncoder().encode(Selection(day: day, discID: featured.id, recentIDs: recentIDs)) {
            defaults.set(data, forKey: key)
        }
        return featured.id
    }
}

@MainActor extension ListeningRoomCoordinator {
    /// Artists stay on the shelf before their discs arrive.
    var showsRack: Bool {
        let groups = rackGroups
        if onlyArtistID != nil, !groups.isEmpty { return true }
        if groups.contains(where: { $0.head != nil }) { return true }
        switch display.catalogChrome {
        case .connectArtist, .empty: return !groups.isEmpty
        case .preparing, .needsMusicAccess, .unavailable: return false
        }
    }

    var rackGroups: [ListeningRackGroup] {
        var groups: [ListeningRackGroup] = []
        if !compilationDiscs.isEmpty {
            groups.append(ListeningRackGroup(
                id: "live",
                kind: .live,
                name: ListeningCopy.text("现场预习"),
                artworkURL: nil,
                discs: compilationDiscs
            ))
        }
        let performances = (show?.timetable?.orderedDays ?? []).flatMap(\.performances).map {
            ListeningRackOrdering.Performance(artistName: $0.artistName, startsAt: $0.startsAt, isInterested: $0.isInterested)
        }
        let order = ListeningRackOrdering.order(names: browseArtists.map(\.name), performances: performances)
        let ordered = order.map { browseArtists[$0] }
        // Artists without an Apple Music identity have nothing to play, so they wait at the end.
        let artists = ordered.filter(\.isConnected) + ordered.filter { !$0.isConnected }
        var seen = Set<String>()
        for artist in artists where seen.insert(artist.id).inserted {
            // Releases lead so a playlist that arrives later never replaces the head disc.
            let discs = artist.albums
            let allReleases = discs.filter { if case .featuredPlaylist = $0.origin { false } else { true } }
            // Singles trail full releases.
            let releases = allReleases.filter { $0.isSingle != true } + allReleases.filter { $0.isSingle == true }
            let releaseIDs = Set(releases.map(\.id))
            let orderedDiscs = releases + discs.filter { !releaseIDs.contains($0.id) }
            let featuredID = show.flatMap {
                ListeningDailyFeaturedDiscPolicy.featuredDiscID(
                    showID: $0.id, artistID: artist.id, discs: orderedDiscs,
                    topSongIDs: artistPresentations[artist.id]?.top.map(\.id) ?? [],
                    familiarSongIDs: familiarSongIDs
                )
            }
            groups.append(ListeningRackGroup(
                // Keyed by lineup slot so connecting an artist keeps the rack's place on it.
                id: "slot-\(artist.slotIndex)",
                kind: .artist(id: artist.id, slotIndex: artist.slotIndex, isConnected: artist.isConnected),
                name: artist.name,
                artworkURL: artist.artworkURL,
                discs: orderedDiscs,
                featuredDiscID: featuredID,
                catalogStatus: artistCatalogStatus[artist.id],
                hasCatalog: !artist.isConnected || catalogSnapshots.contains { $0.artistID == artist.id }
            ))
        }
        return groups
    }
}
