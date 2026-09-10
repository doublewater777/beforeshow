import Foundation
import SwiftData

@MainActor @Observable final class FootprintListeningCoordinator {
    private let context: ModelContext
    let show: Show
    private(set) var tiers: [ShowOpeningArtistTier] = []
    private(set) var wantedCount = 0
    private(set) var memories: [ShowSetlistMemory] = []
    private(set) var songs: [CatalogSong] = []
    private(set) var catalogChoices: [CatalogSong] = []
    private(set) var heardSongIDs: Set<String> = []
    var error: String?
    var canRecall: Bool {
        show.endedAt != nil || show.wasAddedAsHistorical == true ||
        (CurrentShowTimeState(show: show, calendar: show.timingCalendar()).endBoundary.map { $0 < Date() } ?? false)
    }
    init(context: ModelContext, show: Show) { self.context = context; self.show = show }
    func reload() {
        do {
            tiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).filter { $0.showID == show.id }
            wantedCount = try context.fetch(FetchDescriptor<ShowWantsLiveSong>()).filter { $0.showID == show.id }.count
            memories = try context.fetch(FetchDescriptor<ShowSetlistMemory>()).filter { $0.showID == show.id }.sorted { $0.createdAt < $1.createdAt }
            songs = try context.fetch(FetchDescriptor<CatalogSong>())
            let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
            heardSongIDs = Set(records.compactMap { $0.actualListeningAt != nil || $0.manualConfirmedAt != nil ? $0.songID : nil })
            let ids = Set(show.artists.compactMap(\.appleMusicArtistID))
            let snapshots = try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).filter { ids.contains($0.artistID) }
            let songIDs = Set(snapshots.flatMap(\.orderedSongIDs))
            catalogChoices = songs.filter { songIDs.contains($0.appleMusicSongID) }.sorted { a, b in
                let aHeard = heardSongIDs.contains(a.appleMusicSongID)
                let bHeard = heardSongIDs.contains(b.appleMusicSongID)
                if aHeard != bHeard { return aHeard && !bHeard }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
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
    func add(songID: String? = nil, title: String = "", artist: String = "", surprising: Bool = false) {
        guard canRecall else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard songID != nil || !title.isEmpty else { return }
        mutate {
            let row: ShowSetlistMemory
            if let songID, let existing = memories.first(where: { $0.catalogSongID == songID }) { row = existing }
            else {
                row = try ListeningRepository(modelContext: context).addSetlistMemory(showID: show.id,
                    catalogSongID: songID, manualTitle: songID == nil ? title : nil,
                    manualArtistName: songID == nil ? artist : nil)
            }
            if surprising { setSurprisingRows(row) }
        }
    }
    func setSurprising(_ row: ShowSetlistMemory) {
        guard row.showID == show.id else { return }
        mutate { setSurprisingRows(row) }
    }
    func toggleSurprising(_ row: ShowSetlistMemory) {
        guard row.showID == show.id else { return }
        mutate {
            if row.isMostSurprising {
                row.isMostSurprising = false
                row.updatedAt = Date()
            } else {
                setSurprisingRows(row)
            }
        }
    }
    private func setSurprisingRows(_ target: ShowSetlistMemory) {
        for row in memories where row.isMostSurprising && row.id != target.id { row.isMostSurprising = false }
        target.isMostSurprising = true; target.updatedAt = Date()
    }
    func delete(_ row: ShowSetlistMemory) {
        guard row.showID == show.id else { return }
        mutate { try ListeningRepository(modelContext: context).deleteSetlistMemory(row) }
    }
    private func mutate(_ body: () throws -> Void) {
        do { try body(); try context.save(); reload() }
        catch { context.rollback(); self.error = BSLocalization.text("保存失败，请重试") }
    }
}
