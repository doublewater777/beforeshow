import Foundation

// MARK: - Setlist

struct FootprintSetlistSong: Identifiable, Equatable {
    let id: String
    let title: String
    let artistName: String
    /// 听到这首歌的场次，按时间从早到晚。
    let showIDs: [UUID]
    let lastHeard: Date

    var count: Int { showIDs.count }
}

enum FootprintSetlistTab: CaseIterable, Hashable {
    case most, once, artist

    var title: String {
        switch self {
        case .most: return BSLocalization.text("听得最多")
        case .once: return BSLocalization.text("只听过一次")
        case .artist: return BSLocalization.text("按艺人")
        }
    }
}

enum FootprintSetlistArchive {
    /// 所有已归档场次的「现场听到了」合成一张歌单；同一首歌按场次去重计数。
    static func songs(
        memories: [ShowSetlistMemory],
        shows: [Show],
        catalogSongs: [String: CatalogSong] = [:]
    ) -> [FootprintSetlistSong] {
        let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: (title: String, artist: String, shows: [Show])] = [:]
        for memory in memories {
            guard memory.isPlayed else { continue }
            guard let show = showsByID[memory.showID] else { continue }
            let catalog = memory.catalogSongID.flatMap { catalogSongs[$0] }
            let title = catalog?.title ?? memory.manualTitle ?? ""
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let artist = catalog?.artistName ?? memory.manualArtistName ?? ""
            let key = memory.catalogSongID.map { "id:\($0)" }
                ?? "t:\(ShowSetlistRecording.normalized(title))|\(ShowSetlistRecording.normalized(artist))"
            var entry = grouped[key] ?? (title, artist, [])
            if !entry.shows.contains(where: { $0.id == show.id }) { entry.shows.append(show) }
            grouped[key] = entry
        }
        return grouped.map { key, entry in
            let ordered = entry.shows.sorted { $0.effectiveDate < $1.effectiveDate }
            return FootprintSetlistSong(
                id: key,
                title: entry.title,
                artistName: entry.artist,
                showIDs: ordered.map(\.id),
                lastHeard: ordered.last?.effectiveDate ?? .distantPast
            )
        }
        .sorted(by: mostHeardFirst)
    }

    static func list(_ songs: [FootprintSetlistSong], tab: FootprintSetlistTab) -> [FootprintSetlistSong] {
        switch tab {
        case .most:
            return songs.sorted(by: mostHeardFirst)
        case .once:
            return songs.filter { $0.count == 1 }.sorted { $0.lastHeard > $1.lastHeard }
        case .artist:
            return songs.sorted {
                let order = $0.artistName.localizedStandardCompare($1.artistName)
                if order != .orderedSame { return order == .orderedAscending }
                return mostHeardFirst($0, $1)
            }
        }
    }

    private static func mostHeardFirst(_ a: FootprintSetlistSong, _ b: FootprintSetlistSong) -> Bool {
        if a.count != b.count { return a.count > b.count }
        if a.lastHeard != b.lastHeard { return a.lastHeard > b.lastHeard }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

// MARK: - Companions

struct FootprintCompanionBand: Identifiable, Equatable {
    let id: String
    let name: String
    /// 一起去的场次，最近的在前。
    let showIDs: [UUID]
    let topArtist: String?
    let topArtistCount: Int

    var count: Int { showIDs.count }
}

enum FootprintCompanionArchive {
    static func bands(shows: [Show]) -> [FootprintCompanionBand] {
        var byName: [String: [Show]] = [:]
        for show in shows {
            for name in names(of: show) {
                byName[name, default: []].append(show)
            }
        }
        return byName.map { name, shared in
            let ordered = shared.sorted { $0.effectiveDate > $1.effectiveDate }
            let top = topArtist(in: ordered)
            return FootprintCompanionBand(id: name, name: name, showIDs: ordered.map(\.id), topArtist: top?.name, topArtistCount: top?.count ?? 0)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func names(of show: Show) -> [String] {
        CompanionNameList.normalized(show.companionNames)
    }

    /// 并列时取最近一起看过的那位。
    private static func topArtist(in showsNewestFirst: [Show]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for show in showsNewestFirst {
            for name in Set(show.artistNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) {
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        guard let best = order.max(by: { counts[$0]! < counts[$1]! || (counts[$0]! == counts[$1]! && order.firstIndex(of: $0)! > order.firstIndex(of: $1)!) }) else { return nil }
        return (best, counts[best]!)
    }
}

// MARK: - Merch

struct FootprintMerchShelf: Identifiable {
    let year: Int
    let items: [MerchItem]
    var id: Int { year }
}

enum FootprintMerchArchive {
    /// 一层 = 一年，最近的一年在最上层。
    static func shelves(items: [MerchItem], shows: [Show]) -> [FootprintMerchShelf] {
        let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byYear: [Int: [(MerchItem, Show)]] = [:]
        for item in items {
            guard let show = showsByID[item.showID] else { continue }
            let year = show.timingCalendar().component(.year, from: show.effectiveDate)
            byYear[year, default: []].append((item, show))
        }
        return byYear.keys.sorted(by: >).map { year in
            let ordered = byYear[year]!.sorted {
                $0.1.effectiveDate != $1.1.effectiveDate ? $0.1.effectiveDate > $1.1.effectiveDate : $0.0.createdAt < $1.0.createdAt
            }
            return FootprintMerchShelf(year: year, items: ordered.map(\.0))
        }
    }
}
