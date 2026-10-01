import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class ListeningLocalizationTests: XCTestCase {
    func testAllListeningLiteralKeysExistInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        var keys = Set(["想现场听", "开场前想现场听", "当前现场", "只听这位", "回到整场", "不听这位", "恢复", "接下来", "下一位", "热门", "全部", "尚未匹配艺人", "暂时无法更新", "暂时无法载入音乐"])
        let regex = try NSRegularExpression(pattern: #"BSLocalization\.text\("([^"\\]+)"\)"#)
        for subdir in ["Features/Listening", "Features/Footprints"] {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(subdir), includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                if subdir.contains("Footprints") && !url.lastPathComponent.contains("Listening") && !url.lastPathComponent.contains("Setlist") { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                let ns = source as NSString
                for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) { keys.insert(ns.substring(with: match.range(at: 1))) }
            }
        }
        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(locale).lproj/Localizable.strings"))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in keys { XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)") }
        }
    }

    func testListeningCapabilityProjectionCopyExistsInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        let keys: Set<String> = [
            "连接中…", "完整播放", "试听模式", "仅歌曲信息", "暂不可播放",
            "立即授权", "打开设置", "重试", "试听", "部分曲目可试听", "30 秒试听",
            "载入中…", "试听中 · 剩余 %d 秒", "播放中", "试听暂停 · 剩余 %d 秒",
            "暂停", "停止", "播放结束", "暂时无法播放", "选择一张唱片开始播放",
            "当前仅提供歌曲信息", "当前暂不可播放", "请先合上播放器上盖", "热门合辑",
            "仅提供歌曲信息", "授权后载入唱片", "放置唱片中…",
            "允许访问 Apple Music 后，可尝试完整播放。",
            "允许访问 Apple Music 后，可尝试完整播放；当前没有可用试听片段。",
            "当前未允许访问 Apple Music。",
            "当前未允许访问 Apple Music，且这些歌曲没有可用试听片段。",
            "当前 Apple Music 账户不支持完整播放，因此使用歌曲试听片段。",
            "当前 Apple Music 账户不支持完整播放，这些歌曲也没有可用试听片段。",
            "暂时无法确认之后的完整播放权限。",
            "暂时无法确认完整播放权限，当前使用试听片段。",
            "暂时无法确认完整播放权限，这些歌曲也没有可用试听片段。",
            "当前使用歌曲试听片段。", "当前没有可播放的歌曲。",
            "Apple Music 访问受到系统限制，当前使用歌曲试听片段。",
            "Apple Music 访问受到系统限制，且这些歌曲没有可用试听片段。",
            "Apple Music 访问受到系统限制，无法在此更改。",
            "选一场现场，听听即将相遇的音乐。", "添加一场想去的现场，唱片就从这里开始。", "选择对应的 Apple Music 艺人", "连接 %@", "正在搜索艺人…", "换个名字搜索", "清除搜索", "装入并试听", "%@ 等 %d 位艺人"
        ]

        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(locale).lproj/Listening.strings"))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(Set(values.keys), keys)
            for key in keys {
                XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)")
            }
            XCTAssertTrue(values["试听中 · 剩余 %d 秒"]?.contains("%d") == true)
            XCTAssertTrue(values["试听暂停 · 剩余 %d 秒"]?.contains("%d") == true)
        }
    }
}

@MainActor
final class ListeningReviewerRegressionTests: XCTestCase {
    func testCurrentShowChangeClearsOldChromeAndLoadedDisc() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let firstShow = try Show(name: "First", date: now, startTime: now)
        let secondShow = try Show(name: "Second", date: now.addingTimeInterval(60), startTime: now.addingTimeInterval(60))
        context.insert(firstShow)
        context.insert(secondShow)

        let song = CatalogSong(
            appleMusicSongID: "review-song",
            title: "Review Song",
            artistName: "Artist",
            duration: 180,
            previewURL: "https://example.invalid/review.m4a"
        )
        let disc = ListeningDisc(
            id: "review-disc",
            title: "Review Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let prepared = await ListeningChromeBootstrapper.prepare(
            show: firstShow,
            context: context,
            catalogService: ListeningReviewerCatalogStub()
        )
        let firstRoom = try XCTUnwrap(prepared)
        XCTAssertEqual(firstRoom.show?.id, firstShow.id)
        XCTAssertTrue(ListeningPlaybackChromeStore.shared.room.map { $0 === firstRoom } == true)
        XCTAssertTrue(ListeningRoomCache.shared.map { $0 === firstRoom } == true)

        let secondRoom = await ListeningChromeBootstrapper.prepare(
            show: secondShow,
            context: context,
            catalogService: ListeningReviewerCatalogStub()
        )

        XCTAssertNil(secondRoom, "A disc restored for the previous Current Show must not appear under the new Current Show")
        XCTAssertNil(ListeningPlaybackChromeStore.shared.room)
        XCTAssertNil(ListeningRoomCache.shared)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 0)
        XCTAssertFalse(firstRoom.mechanism.hasDisc)
    }

    func testRootAndDestinationsHideTheNativeSystemTabBar() throws {
        let rootView = try listeningSource("RootView.swift")
        XCTAssertTrue(
            rootView.contains("ZStack") && !rootView.contains("TabView(selection:"),
            "RootView uses a custom ZStack to prevent system tab bar flashing on cold start"
        )
        XCTAssertTrue(
            rootView.contains(".modifier(ListeningRootChromeModifier(selectedTab: $selectedTab))"),
            "RootView must mount detached Bottom Chrome"
        )
    }

    private func resetChromeGlobals() {
        ListeningPlaybackChromeStore.shared.room = nil
        ListeningRoomCache.shared?.mechanism.motion.stop()
        ListeningRoomCache.shared = nil
    }

    private func listeningSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private struct ListeningReviewerCatalogStub: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }

    func currentAccess() async -> ListeningMusicAccess {
        ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}
