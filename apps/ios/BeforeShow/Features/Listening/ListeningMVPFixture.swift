#if DEBUG
import SwiftData
import Foundation

/// Explicit visual-QA mode. The entire fixture lives in an in-memory store;
/// it never adds shows, evidence or metadata to the user's persistent database.
@MainActor enum ListeningMVPFixture {
    static func containerIfRequested() -> ModelContainer? {
        guard ProcessInfo.processInfo.arguments.contains("--listening-fixture") else { return nil }
        do {
            let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
            let context = container.mainContext
            let start = Date().addingTimeInterval(86400 * 10)
            let show = try Show(name: "夜航 · 听前预演", date: start, startTime: start)
            show.artists = [ArtistSlot(name: "夜航", avatarURL: nil, appleMusicArtistID: "listen-fixture-artist")]
            context.insert(show)
            let names = ["夜色", "最后一班车", "微光", "蓝色时刻", "慢镜头", "海岸线"]
            for (index, name) in names.enumerated() {
                context.insert(CatalogSong(appleMusicSongID: "listen-fixture-\(index)", title: name, artistName: "夜航", duration: 180))
            }
            for index in 0..<2 {
                context.insert(CatalogAlbum(appleMusicAlbumID: "listen-fixture-album-\(index)", title: index == 0 ? "夜航" : "蓝色时刻",
                    orderedTrackIDs: (index * 3..<index * 3 + 3).map { "listen-fixture-\($0)" }))
            }
            context.insert(ArtistCatalogSnapshot(artistID: "listen-fixture-artist", artistName: "夜航",
                orderedSongIDs: (0..<6).map { "listen-fixture-\($0)" }, albumIDs: ["listen-fixture-album-0", "listen-fixture-album-1"]))
            try context.save()
            return container
        } catch { assertionFailure("Listening fixture setup failed: \(error)"); return nil }
    }
}
#endif
