import Foundation
import XCTest
import SwiftData
@testable import BeforeShow

@MainActor enum ListenTestData {
    static func make(ended: Bool = false) throws -> (ModelContainer, Show) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(ended ? -10000 : 10000)
        let show = try Show(name: "Test Show", date: start, startTime: start)
        if ended { show.endedAt = start.addingTimeInterval(100) }
        show.artists = [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a"),
                        ArtistSlot(name: "B", avatarURL: nil), ArtistSlot(name: "C", avatarURL: nil, appleMusicArtistID: "c")]
        context.insert(show)
        for id in ["a1", "a2", "c1"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: String(id.prefix(1)), duration: 100))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "a", artistName: "A", orderedSongIDs: ["a1", "a2"], topSongIDs: ["a2"], albumIDs: ["album"]))
        context.insert(ArtistCatalogSnapshot(artistID: "c", artistName: "C", orderedSongIDs: ["c1"]))
        context.insert(CatalogAlbum(appleMusicAlbumID: "album", title: "Album", artistIDs: ["a"], orderedTrackIDs: ["a2", "a1"]))
        try context.save()
        return (container, show)
    }
    static func room(_ context: ModelContext) -> ListeningRoomCoordinator {
        ListeningRoomCoordinator(context: context, catalogService: ListenTestCatalog(), artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { ListeningFixturePlayer(source: $0) })
    }
    static func settle(_ room: ListeningRoomCoordinator, until condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            let m = room.mechanism.motion
            m.lid.step(1); m.discX.step(1); m.discY.step(1); m.lift.step(1); m.discScale.step(1)
            room.mechanism.refresh()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Physical operation did not settle")
    }
}
private struct ListenTestCatalog: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { .init(authorizationStatus: .authorized, canPlayCatalogContent: true) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload { throw ListeningCatalogError.artistNotFound(artistID) }
}
