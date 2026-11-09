import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowSetlistPlaybackTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, ShowSetlistMemory.self, CatalogSong.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeShow() throws -> Show {
        try Show(
            name: "告五人 宇宙的有趣",
            date: Date(),
            startTime: Date(),
            timeZoneIdentifier: "Asia/Shanghai",
            artists: [ArtistSlot(name: "告五人")]
        )
    }

    private let catalog = [
        CatalogSong(appleMusicSongID: "s1", title: "给你一瓶魔法药水", artistName: "告五人", artworkURL: "https://a/1.jpg", duration: 200, previewURL: "https://p/1.m4a"),
        CatalogSong(appleMusicSongID: "s2", title: "爱人错过", artistName: "告五人", previewURL: "https://p/2.m4a")
    ]

    private func song(_ id: String?, _ title: String) -> ShowSetlistRecording.Song {
        .init(catalogSongID: id, title: title, artistName: "告五人")
    }

    func testPreviewAndReplayDiscsHaveDifferentIdentities() throws {
        let show = try makeShow()
        let preview = ShowSetlistPlayback.disc([song("s1", "给你一瓶魔法药水"), song("s2", "爱人错过")], show: show, kind: .preview, title: "预习歌单", catalog: catalog)
        let replay = ShowSetlistPlayback.disc([song("s2", "爱人错过")], show: show, kind: .replay, title: show.name, catalog: catalog)

        XCTAssertNotEqual(preview?.id, replay?.id)
    }

    func testSameSongsBuildEqualDiscSoReplayResumesInsteadOfReloading() throws {
        let show = try makeShow()
        let songs = [song("s1", "给你一瓶魔法药水"), song(nil, "爱人错过")]
        let first = ShowSetlistPlayback.disc(songs, show: show, kind: .replay, title: show.name, catalog: catalog)
        let second = ShowSetlistPlayback.disc(songs, show: show, kind: .replay, title: show.name, catalog: catalog)

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testTracksCarryCatalogPreviewAndManualSongsMatchCatalogByTitle() throws {
        let show = try makeShow()
        let disc = try XCTUnwrap(ShowSetlistPlayback.disc(
            [song("s1", "给你一瓶魔法药水"), song(nil, " 爱人错过 "), song(nil, "截图里认不出的歌")],
            show: show, kind: .replay, title: show.name, catalog: catalog
        ))

        XCTAssertEqual(disc.tracks.map(\.id), ["s1", "s2"], "Unmatched manual songs must not become fake catalog IDs")
        XCTAssertEqual(disc.tracks.map(\.previewURL), [URL(string: "https://p/1.m4a"), URL(string: "https://p/2.m4a")])
        XCTAssertEqual(disc.tracks.first?.duration, 200)
    }

    func testEncoreRepeatPlaysOnceSoTrackIDsStayUnique() throws {
        let show = try makeShow()
        let disc = try XCTUnwrap(ShowSetlistPlayback.disc(
            [song("s1", "给你一瓶魔法药水"), song("s2", "爱人错过"), song(nil, "给你一瓶魔法药水")],
            show: show, kind: .replay, title: show.name, catalog: catalog
        ))

        XCTAssertEqual(disc.tracks.map(\.id), ["s1", "s2"])
    }

    func testNoPlayableSongsBuildsNoDisc() throws {
        let show = try makeShow()
        XCTAssertNil(ShowSetlistPlayback.disc([song(nil, "认不出")], show: show, kind: .replay, title: show.name, catalog: catalog))
    }

    func testReplaySongsKeepLegacyCatalogRecordsAndOrderByCreatedAt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)
        let start = Date(timeIntervalSince1970: 1_000)
        context.insert(ShowSetlistMemory(showID: show.id, catalogSongID: "s1", createdAt: start.addingTimeInterval(20)))
        context.insert(ShowSetlistMemory(showID: show.id, manualTitle: "爱人错过", manualArtistName: "告五人", createdAt: start.addingTimeInterval(10)))
        context.insert(ShowSetlistMemory(showID: show.id, manualTitle: "未唱", manualArtistName: "告五人", wasPlayed: false, createdAt: start))
        catalog.forEach(context.insert)

        let disc = try XCTUnwrap(ShowSetlistPlayback.replayDisc(for: show, in: context))

        XCTAssertEqual(disc.tracks.map(\.id), ["s2", "s1"])
        XCTAssertEqual(disc.tracks.map(\.title), ["爱人错过", "给你一瓶魔法药水"])
    }

    func testHasPlayableSongsSkipsCatalogWhenNoPlayedMemories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)
        catalog.forEach(context.insert)

        XCTAssertFalse(ShowSetlistPlayback.hasPlayableSongs(for: show, in: context))
    }

    func testHasPlayableSongsReturnsTrueWhenPlayedSongHasCatalogID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)
        context.insert(ShowSetlistMemory(showID: show.id, catalogSongID: "s1", wasPlayed: true))

        XCTAssertTrue(ShowSetlistPlayback.hasPlayableSongs(for: show, in: context))
    }
}
