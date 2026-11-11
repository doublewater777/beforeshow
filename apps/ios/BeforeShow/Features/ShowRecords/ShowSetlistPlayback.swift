import Foundation
import SwiftData

/// 把这场记下的歌单作为一张唱片放进共用播放机。
@MainActor
enum ShowSetlistPlayback {
    enum Kind: String {
        case preview
        case replay
    }

    static func discID(for show: Show, kind: Kind) -> String { "setlist-\(kind.rawValue)-\(show.id.uuidString)" }

    /// 散场后的「今晚唱过」，能在「听」目录里对上的才进唱片。
    static func replayDisc(for show: Show, in context: ModelContext) -> ListeningDisc? {
        let memories = (try? ShowSetlistRecording.memories(showID: show.id, in: context)) ?? []
        let songs = ShowSetlistRecording.played(memories).map {
            ShowSetlistRecording.Song(
                catalogSongID: $0.catalogSongID,
                title: $0.manualTitle ?? "",
                artistName: $0.manualArtistName ?? ""
            )
        }
        guard !songs.isEmpty else { return nil }
        return disc(songs, show: show, kind: .replay, title: show.name, catalog: catalog(for: songs, in: context))
    }

    /// 散场后是否有能放出的歌，避免首页每次刷新都做多余的目录匹配。
    static func hasPlayableSongs(for show: Show, in context: ModelContext) -> Bool {
        let memories = (try? ShowSetlistRecording.memories(showID: show.id, in: context)) ?? []
        let played = ShowSetlistRecording.played(memories)
        guard !played.isEmpty else { return false }
        if played.contains(where: { $0.catalogSongID != nil }) { return true }
        return replayDisc(for: show, in: context) != nil
    }

    static func catalog(in context: ModelContext) -> [CatalogSong] {
        (try? context.fetch(FetchDescriptor<CatalogSong>())) ?? []
    }

    /// 只取这份歌单可能对上的目录歌。全由目录添加时走精准 ID 查询；含手录歌名时保留完整目录以支持大小写不敏感匹配。
    static func catalog(for songs: [ShowSetlistRecording.Song], in context: ModelContext) -> [CatalogSong] {
        let hasManualTitles = songs.contains { $0.catalogSongID == nil && !$0.title.isEmpty }
        if !hasManualTitles {
            let ids = songs.compactMap(\.catalogSongID)
            guard !ids.isEmpty else { return [] }
            let descriptor = FetchDescriptor<CatalogSong>(predicate: #Predicate {
                ids.contains($0.appleMusicSongID)
            })
            return (try? context.fetch(descriptor)) ?? []
        }
        return catalog(in: context)
    }

    /// 曲目一律落到目录里的歌：带上试听地址、封面和时长；手动/截图的歌按歌名和艺人对上，对不上的不放。
    static func disc(
        _ songs: [ShowSetlistRecording.Song],
        show: Show,
        kind: Kind,
        title: String,
        catalog: [CatalogSong]
    ) -> ListeningDisc? {
        let byID = Dictionary(catalog.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        // 返场重唱的歌只放一次：播放机按曲目 ID 定位上下首。
        let tracks = songs.compactMap { song -> ListeningDiscTrack? in
            guard let match = song.catalogSongID.flatMap({ byID[$0] }) ?? catalogMatch(for: song, in: catalog),
                  seen.insert(match.appleMusicSongID).inserted else { return nil }
            return ListeningDiscTrack(
                id: match.appleMusicSongID,
                title: match.title,
                artistName: match.artistName,
                artworkURL: match.artworkURL.flatMap(URL.init(string:)),
                duration: match.duration,
                previewURL: match.previewURL.flatMap(URL.init(string:))
            )
        }
        guard !tracks.isEmpty else { return nil }
        return ListeningDisc(
            id: discID(for: show, kind: kind),
            title: title,
            artworkURL: ShowCoverReference.url(show.coverImageURL),
            tracks: tracks,
            artistNames: show.artistNames,
            origin: .compilation(showID: show.id, number: 0)
        )
    }

    /// 同一张唱片已在播放机里就接着放，内容变了才重新装入。返回是否放上了。
    @discardableResult
    static func play(_ disc: ListeningDisc?) async -> Bool {
        guard let disc, let room = await ListeningIntentHandler.shared.roomForPlayback() else { return false }
        if room.loadedDisc == disc {
            if !room.wantsPlayback { room.playPause() }
        } else {
            room.loadDisc(disc, autoplay: true)
        }
        ListeningRoomSessionStore.shared.publishChrome(room)
        return true
    }

    private static func catalogMatch(for song: ShowSetlistRecording.Song, in catalog: [CatalogSong]) -> CatalogSong? {
        let title = ShowSetlistRecording.normalized(song.title)
        guard !title.isEmpty else { return nil }
        let artist = ShowSetlistRecording.normalized(song.artistName)
        return catalog.first {
            ShowSetlistRecording.normalized($0.title) == title
                && (artist.isEmpty || ShowSetlistRecording.normalized($0.artistName).contains(artist))
        }
    }
}
