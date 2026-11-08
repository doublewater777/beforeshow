import Foundation
import SwiftData

/// 「现场听到了」的写入口。曲目来自「听」已缓存的目录时同时记下歌名快照，
/// 目录缓存被清掉后歌单归档仍能显示。
enum ShowSetlistRecording {
    struct Song: Hashable {
        let catalogSongID: String?
        let title: String
        let artistName: String
    }

    static func memories(showID: UUID, in context: ModelContext) throws -> [ShowSetlistMemory] {
        try context.fetch(FetchDescriptor<ShowSetlistMemory>(
            predicate: #Predicate { $0.showID == showID },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    /// 已记 → 移除；未记 → 记下。返回切换后是否已记。
    @discardableResult
    static func toggle(_ song: Song, showID: UUID, in context: ModelContext, wasPlayed: Bool? = nil, now: Date = Date()) throws -> Bool {
        let existing = try memories(showID: showID, in: context).filter { matches($0, song) }
        if !existing.isEmpty {
            existing.forEach(context.delete)
            return false
        }
        context.insert(ShowSetlistMemory(
            showID: showID,
            catalogSongID: song.catalogSongID,
            manualTitle: song.title,
            manualArtistName: song.artistName,
            wasPlayed: wasPlayed,
            createdAt: now,
            updatedAt: now
        ))
        return true
    }

    /// 标记是否已唱（演出中打勾，不从单子中删除）。
    @discardableResult
    static func togglePlayed(_ song: Song, showID: UUID, in context: ModelContext, now: Date = Date()) throws -> Bool {
        if let existing = try memories(showID: showID, in: context).first(where: { matches($0, song) }) {
            let next = !(existing.wasPlayed ?? false)
            existing.wasPlayed = next
            existing.updatedAt = now
            return next
        }
        let memory = ShowSetlistMemory(
            showID: showID,
            catalogSongID: song.catalogSongID,
            manualTitle: song.title,
            manualArtistName: song.artistName,
            wasPlayed: true,
            createdAt: now,
            updatedAt: now
        )
        context.insert(memory)
        return true
    }

    /// 手动输入不在列表里的歌；空白或已记过的同名歌不重复写。
    static func addManual(
        title: String,
        artistName: String,
        showID: UUID,
        in context: ModelContext,
        wasPlayed: Bool? = nil,
        isMostSurprising: Bool = false,
        order: Int? = nil,
        now: Date = Date()
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let song = Song(catalogSongID: nil, title: trimmed, artistName: artistName)
        let list = try memories(showID: showID, in: context)
        if let existing = list.first(where: { matches($0, song) }) {
            if let wasPlayed { existing.wasPlayed = wasPlayed }
            if isMostSurprising { existing.isMostSurprising = true }
            existing.updatedAt = now
            return
        }
        context.insert(ShowSetlistMemory(
            showID: showID,
            catalogSongID: nil,
            manualTitle: trimmed,
            manualArtistName: artistName,
            isMostSurprising: isMostSurprising,
            wasPlayed: wasPlayed,
            order: order ?? (list.count + 1),
            createdAt: now,
            updatedAt: now
        ))
    }

    static func matches(_ memory: ShowSetlistMemory, _ song: Song) -> Bool {
        if let id = song.catalogSongID { return memory.catalogSongID == id }
        return memory.catalogSongID == nil
            && normalized(memory.manualTitle) == normalized(song.title)
            && normalized(memory.manualArtistName) == normalized(song.artistName)
    }

    static func normalized(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
