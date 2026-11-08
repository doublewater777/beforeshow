import Foundation

/// 每种记录一组徽章，铜 / 银 / 金三档；全部由已有记录推导，不另存进度。
enum FootprintBadgeFamily: String, CaseIterable, Identifiable {
    case memory, setlist, encore, merch, ledger, ticket, timetable, companion, buddy, ritual, cities, venue, artist

    var id: String { rawValue }

    /// 三档门槛，按从低到高。
    var targets: [Int] {
        switch self {
        case .memory: return [1, 30, 100]
        case .setlist: return [1, 50, 200]
        case .encore: return [2, 3, 5]
        case .merch: return [1, 10, 30]
        case .ledger: return [1, 10, 30]
        case .ticket: return [1, 10, 30]
        case .timetable: return [1, 5, 15]
        case .companion: return [1, 10, 30]
        case .buddy: return [3, 5, 10]
        case .ritual: return [1, 10, 30]
        case .cities: return [3, 5, 10]
        case .venue: return [3, 5, 10]
        case .artist: return [2, 3, 5]
        }
    }

    var symbol: String {
        switch self {
        case .memory: return "camera.fill"
        case .setlist: return "music.note"
        case .encore: return "repeat"
        case .merch: return "tshirt.fill"
        case .ledger: return "receipt"
        case .ticket: return "ticket.fill"
        case .timetable: return "list.bullet.rectangle"
        case .companion: return "person.2.fill"
        case .buddy: return "hands.clap.fill"
        case .ritual: return "star.fill"
        case .cities: return "map.fill"
        case .venue: return "building.2.fill"
        case .artist: return "music.mic"
        }
    }

    var title: String {
        switch self {
        case .memory: return BSLocalization.text("碎片收藏家")
        case .setlist: return BSLocalization.text("歌单记录员")
        case .encore: return BSLocalization.text("老歌重逢")
        case .merch: return BSLocalization.text("周边猎人")
        case .ledger: return BSLocalization.text("精打细算")
        case .ticket: return BSLocalization.text("票根夹")
        case .timetable: return BSLocalization.text("排表达人")
        case .companion: return BSLocalization.text("结伴同行")
        case .buddy: return BSLocalization.text("固定搭子")
        case .ritual: return BSLocalization.text("散场留言")
        case .cities: return BSLocalization.text("城市巡演")
        case .venue: return BSLocalization.text("主场")
        case .artist: return BSLocalization.text("铁粉")
        }
    }

    /// 达成条件，%lld 为门槛。
    func requirement(_ target: Int) -> String {
        switch self {
        case .memory: return BSLocalization.format("记下 %lld 条记忆碎片", target)
        case .setlist: return BSLocalization.format("记下 %lld 首现场听到的歌", target)
        case .encore: return BSLocalization.format("同一首歌在 %lld 场现场听到", target)
        case .merch: return BSLocalization.format("收进 %lld 件周边", target)
        case .ledger: return BSLocalization.format("给 %lld 场记下花销", target)
        case .ticket: return BSLocalization.format("保存 %lld 张票根", target)
        case .timetable: return BSLocalization.format("保存 %lld 份时刻表", target)
        case .companion: return BSLocalization.format("和朋友一起去 %lld 场", target)
        case .buddy: return BSLocalization.format("和同一个人一起去 %lld 场", target)
        case .ritual: return BSLocalization.format("散场后留下 %lld 次评价", target)
        case .cities: return BSLocalization.format("在 %lld 座城市看现场", target)
        case .venue: return BSLocalization.format("回到同一个场馆 %lld 次", target)
        case .artist: return BSLocalization.format("看同一位艺人 %lld 场", target)
        }
    }
}

/// 一组徽章的当前进度：已到哪一档、离下一档还差多少。
struct FootprintBadge: Identifiable, Equatable {
    let family: FootprintBadgeFamily
    let progress: Int

    var id: String { family.rawValue }

    /// 0 = 还没解锁，1…3 = 铜银金。
    var tier: Int { family.targets.filter { progress >= $0 }.count }
    var isEarned: Bool { tier > 0 }
    var isMaxed: Bool { tier == family.targets.count }
    var nextTarget: Int? { isMaxed ? nil : family.targets[tier] }
    var remaining: Int { nextTarget.map { max(0, $0 - progress) } ?? 0 }

    /// 解锁过的每一档各有一个 id，用来判断「新」。
    var earnedTierIDs: [String] { (0..<tier).map { "\(family.rawValue)-\($0 + 1)" } }

    /// 当前档到下一档的进度 0…1。
    var fraction: Double {
        guard let next = nextTarget else { return 1 }
        let floor = tier == 0 ? 0 : family.targets[tier - 1]
        return Double(progress - floor) / Double(max(1, next - floor))
    }
}

struct FootprintBadgeFacts: Equatable {
    var memories = 0
    var setlistSongs = 0
    var mostHeardSong = 0
    var merch = 0
    var showsWithSpending = 0
    var tickets = 0
    var timetables = 0
    var showsWithCompanion = 0
    var mostSharedWithOnePerson = 0
    var ritualRatings = 0
    var cities = 0
    var mostVisitedVenue = 0
    var mostSeenArtist = 0

    func progress(for family: FootprintBadgeFamily) -> Int {
        switch family {
        case .memory: return memories
        case .setlist: return setlistSongs
        case .encore: return mostHeardSong
        case .merch: return merch
        case .ledger: return showsWithSpending
        case .ticket: return tickets
        case .timetable: return timetables
        case .companion: return showsWithCompanion
        case .buddy: return mostSharedWithOnePerson
        case .ritual: return ritualRatings
        case .cities: return cities
        case .venue: return mostVisitedVenue
        case .artist: return mostSeenArtist
        }
    }
}

enum FootprintBadgeCatalog {
    /// 已解锁的排前面（高档在前），没解锁的按离下一档最近排。
    static func badges(_ facts: FootprintBadgeFacts) -> [FootprintBadge] {
        FootprintBadgeFamily.allCases
            .map { FootprintBadge(family: $0, progress: facts.progress(for: $0)) }
            .enumerated()
            .sorted { lhs, rhs in
                let a = lhs.element, b = rhs.element
                if a.tier != b.tier { return a.tier > b.tier }
                if !a.isEarned, a.fraction != b.fraction { return a.fraction > b.fraction }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// 只看已归档现场上的记录。
    @MainActor
    static func facts(
        archive: FootprintArchiveSnapshot,
        memories: [ShowSetlistMemory],
        merch: [MerchItem],
        fragments: [MemoryFragment],
        assets: [ShowAsset]
    ) -> FootprintBadgeFacts {
        let shows = archive.shows
        let ids = Set(shows.map(\.id))
        let songs = FootprintSetlistArchive.songs(memories: memories, shows: shows)
        let bands = FootprintCompanionArchive.bands(shows: shows)
        return FootprintBadgeFacts(
            memories: fragments.filter { ids.contains($0.showID) }.count,
            setlistSongs: songs.reduce(0) { $0 + $1.count },
            mostHeardSong: songs.map(\.count).max() ?? 0,
            merch: merch.filter { ids.contains($0.showID) }.count,
            showsWithSpending: shows.filter(\.hasAnySpending).count,
            tickets: Set(assets.filter { $0.kind == .ticket && ids.contains($0.showID) }.map(\.showID)).count,
            timetables: shows.filter { ShowAssetManagementPolicy.hasSavedAsset(for: $0, kind: .timetable, assets: assets) }.count,
            showsWithCompanion: Set(bands.flatMap(\.showIDs)).count,
            mostSharedWithOnePerson: bands.map(\.count).max() ?? 0,
            ritualRatings: shows.filter { $0.rating != nil }.count,
            cities: archive.cities.count,
            mostVisitedVenue: archive.venues.map(\.count).max() ?? 0,
            mostSeenArtist: archive.artists.map(\.count).max() ?? 0
        )
    }
}

/// 看过的徽章档位；新解锁但还没看过的会在徽章墙上掉落一次。
struct FootprintBadgeSeenStore {
    static let key = "footprint.badges.seenTierIDs"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }

    func unseen(in badges: [FootprintBadge]) -> Set<String> {
        Set(badges.flatMap(\.earnedTierIDs)).subtracting(seen)
    }

    func markSeen(_ badges: [FootprintBadge]) {
        defaults.set(Array(seen.union(badges.flatMap(\.earnedTierIDs))).sorted(), forKey: Self.key)
    }
}
