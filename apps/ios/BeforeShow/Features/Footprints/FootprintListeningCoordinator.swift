import Foundation
import SwiftData

@MainActor @Observable final class FootprintListeningCoordinator {
    private let context: ModelContext
    let show: Show
    private(set) var tiers: [ShowOpeningArtistTier] = []
    private(set) var memories: [ShowSetlistMemory] = []
    private(set) var songs: [CatalogSong] = []
    var error: String?
    init(context: ModelContext, show: Show) { self.context = context; self.show = show }
    func reload() {
        do {
            tiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).filter { $0.showID == show.id }
            memories = try context.fetch(FetchDescriptor<ShowSetlistMemory>())
                .filter { $0.showID == show.id && $0.isPlayed }
                .sorted {
                    if let o1 = $0.order, let o2 = $1.order, o1 != o2 { return o1 < o2 }
                    return $0.createdAt < $1.createdAt
                }
            songs = try context.fetch(FetchDescriptor<CatalogSong>())
        } catch { self.error = BSLocalization.text("缓存读取失败") }
    }
    func title(_ memory: ShowSetlistMemory) -> String {
        songs.first { $0.appleMusicSongID == memory.catalogSongID }?.title ?? memory.manualTitle ?? BSLocalization.text("现场听到了")
    }
    func artist(_ memory: ShowSetlistMemory) -> String {
        songs.first { $0.appleMusicSongID == memory.catalogSongID }?.artistName ?? memory.manualArtistName ?? ""
    }
    func artwork(_ memory: ShowSetlistMemory) -> URL? {
        songs.first { $0.appleMusicSongID == memory.catalogSongID }?.artworkURL.flatMap(URL.init(string:))
    }
}
