import Foundation

struct ListeningRuntimeCatalogFetch: Sendable {
    let artistID: String
    let songs: [ListeningCatalogSongPayload]
    let failed: Bool
}

@MainActor
enum ListeningRuntimeCatalogLoader {
    /// Keep at most four requests in flight. A slow artist never blocks the next
    /// request or the publication of another artist's playable songs.
    static func fetch(
        artistIDs: [String],
        service: any ListeningMusicCatalogServicing,
        onResult: (ListeningRuntimeCatalogFetch) -> Void
    ) async {
        await withTaskGroup(of: ListeningRuntimeCatalogFetch.self) { group in
            var remaining = artistIDs.makeIterator()
            func enqueue(_ artistID: String) {
                group.addTask {
                    do {
                        let songs = try await service.fetchRuntimeSongs(artistID: artistID)
                        return ListeningRuntimeCatalogFetch(artistID: artistID, songs: songs, failed: false)
                    } catch {
                        return ListeningRuntimeCatalogFetch(artistID: artistID, songs: [], failed: true)
                    }
                }
            }
            for _ in 0..<4 {
                if let id = remaining.next(), !Task.isCancelled { enqueue(id) }
            }
            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                onResult(result)
                if let id = remaining.next() { enqueue(id) }
            }
        }
    }
}
