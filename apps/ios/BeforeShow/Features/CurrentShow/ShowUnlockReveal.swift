import Foundation
import SwiftData

/// 这场现场散场后解锁的东西：第 N 张数字唱片，以及因为这场才升档的徽章。
struct ShowUnlocks: Equatable {
    let showID: UUID
    /// 这场在足迹里的序号；还没归档时为空。
    var showNumber: Int? = nil
    let record: FootprintNumberSong?
    let badges: [FootprintBadge]

    var isEmpty: Bool { record == nil && badges.isEmpty }
}

@MainActor
enum ShowUnlockReveal {
    static func unlocks(for show: Show, shows: [Show], in context: ModelContext) -> ShowUnlocks {
        unlocks(
            for: show,
            shows: shows,
            memories: (try? context.fetch(FetchDescriptor<ShowSetlistMemory>())) ?? [],
            merch: (try? context.fetch(FetchDescriptor<MerchItem>())) ?? [],
            fragments: (try? context.fetch(FetchDescriptor<MemoryFragment>())) ?? [],
            assets: (try? context.fetch(FetchDescriptor<ShowAsset>())) ?? []
        )
    }

    /// 比较算上和不算这场时的徽章档位，只留这场带来的升档；不依赖任何已看过的基准。
    static func unlocks(
        for show: Show,
        shows: [Show],
        memories: [ShowSetlistMemory],
        merch: [MerchItem],
        fragments: [MemoryFragment],
        assets: [ShowAsset],
        now: Date = Date()
    ) -> ShowUnlocks {
        let with = FootprintArchiveBuilder.make(shows: shows, now: now)
        let chronological = FootprintArchiveRankingBuilder.chronological(with.shows)
        guard let index = chronological.firstIndex(where: { $0.id == show.id }) else {
            return ShowUnlocks(showID: show.id, record: nil, badges: [])
        }
        let without = FootprintArchiveBuilder.make(shows: shows.filter { $0.id != show.id }, now: now)
        func badges(_ archive: FootprintArchiveSnapshot) -> [FootprintBadge] {
            FootprintBadgeCatalog.badges(FootprintBadgeCatalog.facts(
                archive: archive, memories: memories, merch: merch, fragments: fragments, assets: assets
            ))
        }
        let before = Dictionary(uniqueKeysWithValues: badges(without).map { ($0.family, $0.tier) })
        return ShowUnlocks(
            showID: show.id,
            showNumber: index + 1,
            record: FootprintNumberSongs.song(for: index + 1),
            badges: badges(with).filter { $0.tier > (before[$0.family] ?? 0) }
        )
    }
}

/// 每场只在首页揭晓一次。
struct ShowUnlockRevealStore {
    static let key = "home.unlockReveal.shownShowIDs"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func hasShown(_ showID: UUID) -> Bool {
        (defaults.stringArray(forKey: Self.key) ?? []).contains(showID.uuidString)
    }

    func markShown(_ showID: UUID) {
        let shown = Set(defaults.stringArray(forKey: Self.key) ?? []).union([showID.uuidString])
        defaults.set(shown.sorted(), forKey: Self.key)
    }
}
