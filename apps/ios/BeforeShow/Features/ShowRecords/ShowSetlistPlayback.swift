import Foundation
import SwiftData

/// 把这场记下的歌单作为一张唱片放进共用播放机。
@MainActor
enum ShowSetlistPlayback {
    static func discID(for showID: UUID) -> String { "setlist-\(showID.uuidString)" }

    /// 散场后算「今晚唱过」的歌：没标没唱的都算。
    static func playedSongs(showID: UUID, in context: ModelContext) -> [ShowSetlistMemory] {
        let memories = (try? ShowSetlistRecording.memories(showID: showID, in: context)) ?? []
        return memories
            .filter { $0.wasPlayed != false && !($0.manualTitle ?? "").isEmpty }
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
    }

    static func play(_ songs: [(catalogSongID: String?, title: String, artistName: String)], show: Show, title: String) async {
        guard !songs.isEmpty else { return }
        let disc = ListeningDisc(
            id: discID(for: show.id),
            title: title,
            artworkURL: show.coverImageURL.flatMap(URL.init(string:)),
            tracks: songs.map {
                ListeningDiscTrack(
                    id: $0.catalogSongID ?? UUID().uuidString,
                    title: $0.title,
                    artistName: $0.artistName,
                    artworkURL: nil,
                    duration: nil,
                    previewURL: nil
                )
            },
            artistNames: show.artistNames,
            origin: .compilation(showID: show.id, number: 0)
        )
        guard let room = await ListeningIntentHandler.shared.roomForPlayback() else { return }
        room.loadDisc(disc, autoplay: true)
        ListeningRoomSessionStore.shared.publishChrome(room)
    }
}
