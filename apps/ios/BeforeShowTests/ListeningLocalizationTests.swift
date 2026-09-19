import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class ListeningLocalizationTests: XCTestCase {
    func testAllListeningLiteralKeysAndTierNamesExistInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        var keys = Set(ListeningFamiliarityTier.allCases.map(\.localizationKey))
        keys.formUnion(["想现场听", "开场前想现场听", "当前现场", "只听这位", "回到整场", "不听这位", "恢复", "接下来", "下一位", "热门", "全部", "尚未匹配艺人", "暂时无法更新", "暂时无法载入音乐"])
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
            "仅提供歌曲信息", "授权后载入唱片"
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

    func testCompactRootBarAccessibilityAndReduceMotionContractsAreLockedInSource() throws {
        let listeningRoot = try listeningSource("Features/Listening/Views/ListeningPolishedBottomChrome.swift")

        XCTAssertTrue(
            listeningRoot.contains("static let tabSize: CGFloat = 58"),
            "Detached root buttons must keep a generous touch target"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let gap: CGFloat = 10"),
            "Detached root controls must stay visually grouped instead of drifting to the screen edges"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let playerGroupMaxWidth: CGFloat = 352"),
            "Compact-player mode must remain centered as a tight three-piece group"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let miniPlayerWidth = playerGroupMaxWidth - tabSize * 2 - gap * 2"),
            "Mini-player expansion must use an explicit animatable width"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let iconGroupWidth = tabSize * 3 + gap * 2"),
            "Listen icon mode must use an explicit compact group width"
        )
        XCTAssertFalse(
            listeningRoot.contains("RoundedRectangle(cornerRadius: 30"),
            "Root navigation must not reintroduce a full-width shared dock background"
        )
        XCTAssertTrue(
            listeningRoot.contains("minHeight: BSLayout.minTouchTarget"),
            "Compact player interactions must retain at least a 44pt hit height"
        )
        XCTAssertTrue(
            listeningRoot.contains("paused: reduceMotion || !showsPlayingState"),
            "Disc spin must pause when Reduce Motion is enabled"
        )
        XCTAssertTrue(listeningRoot.contains("\"root.tab.current\""))
        XCTAssertTrue(listeningRoot.contains("\"root.tab.listen\""))
        XCTAssertTrue(listeningRoot.contains("\"root.tab.footprints\""))
        XCTAssertTrue(listeningRoot.contains("\"listening.miniPlayer.playPause\""))
        XCTAssertTrue(
            listeningRoot.contains("accessibilityAddTraits(.isSelected)"),
            "Custom root tabs must preserve the native selected-tab VoiceOver state"
        )
        XCTAssertFalse(
            listeningRoot.contains("matchedGeometryEffect"),
            "Tab switching must not compete with matched-geometry layout animation"
        )
        XCTAssertFalse(
            listeningRoot.contains(".spring("),
            "Root chrome must not run a spring layout animation during TabView selection changes"
        )
        XCTAssertTrue(
            listeningRoot.contains("@State private var presentedTab: BeforeShowTab"),
            "Chrome presentation state must be decoupled from the immediate TabView selection"
        )
        XCTAssertTrue(
            listeningRoot.contains("await Task.yield()"),
            "Chrome presentation must follow after TabView gets the first transition turn"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let transitionDelay = Duration.milliseconds(45)"),
            "Chrome animation must start after the TabView selection frame"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let transitionDuration = 0.28"),
            "Listen contraction/expansion should remain visible instead of snapping"
        )
        XCTAssertTrue(
            listeningRoot.contains("withAnimation(.easeInOut(duration: ListeningBottomBarLayout.transitionDuration))"),
            "Only the deferred chrome update should animate"
        )
        XCTAssertTrue(
            listeningRoot.contains("if reduceMotion {\n                presentedTab = selectedTab"),
            "Reduce Motion must bypass the chrome expansion animation"
        )
        XCTAssertFalse(
            listeningRoot.contains("tabViewBottomAccessoryPlacement"),
            "The root chrome must not depend on the iOS 26 accessory placement environment"
        )
        XCTAssertFalse(
            listeningRoot.contains("Image(systemName: \"eject.fill\")"),
            "The global bottom bar must not expose the CD mechanism control"
        )
    }

    func testListenWarmupAndActivationDoNotCompeteWithInitialTabFrame() throws {
        let rootChrome = try listeningSource("Features/Listening/ListeningFeatureRootView.swift")
        let room = try listeningSource("Features/Listening/Views/ListeningRoomView.swift")

        XCTAssertTrue(
            rootChrome.contains(".task {\n                ListeningPlayerWarmup.prepareIfNeeded()"),
            "CD assets and audio must warm before the user taps Listen"
        )
        XCTAssertFalse(
            rootChrome.contains("if isActive { ListeningPlayerWarmup.prepareIfNeeded() }"),
            "Entering Listen must not start asset warmup in the tab-selection frame"
        )
        XCTAssertFalse(
            room.contains("ListeningPlayerWarmup.prepareIfNeeded()"),
            "Room activation must not perform warmup work"
        )
        XCTAssertTrue(
            room.contains("await Task.yield()"),
            "Listen room lifecycle must yield once so TabView can commit its destination first"
        )
        XCTAssertTrue(
            room.contains(".task(id: activityKey)"),
            "Listen enter/exit work must share one cancellable deferred task"
        )
        XCTAssertFalse(
            room.contains(".onChange(of: isActive)"),
            "Listen lifecycle must not perform synchronous tab-change work"
        )
        XCTAssertTrue(
            room.contains("if isActive { room?.setActive(false) }"),
            "onDisappear must avoid synchronous teardown for ordinary tab switches"
        )
    }

    func testRootUsesStableCompactBarWithoutNativeBottomAccessory() throws {
        let rootChrome = try listeningSource("Features/Listening/ListeningFeatureRootView.swift")
        let rootView = try listeningSource("RootView.swift")

        XCTAssertFalse(rootChrome.contains(".tabViewBottomAccessory"))
        XCTAssertFalse(rootChrome.contains(".tabBarMinimizeBehavior"))
        XCTAssertFalse(rootView.contains(".tabViewBottomAccessory"))
        XCTAssertFalse(rootView.contains(".tabBarMinimizeBehavior"))
        XCTAssertFalse(rootView.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(rootView.contains("ListeningRootChromeModifier(selectedTab: $selectedTab)"))
        XCTAssertTrue(rootChrome.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(rootChrome.contains("ListeningPolishedBottomChrome(selectedTab: $selectedTab)"))
    }

    func testEachRootDestinationHidesTheSystemTabBar() throws {
        for path in [
            "Features/CurrentShow/CurrentShowSession.swift",
            "Features/Listening/ListeningFeatureRootView.swift",
            "Features/Footprints/FootprintsView.swift"
        ] {
            XCTAssertTrue(
                try listeningSource(path).contains(".toolbar(.hidden, for: .tabBar)"),
                "\(path) must hide the native TabView bar so only the custom root chrome is visible"
            )
        }
    }

    func testListenStageDoesNotPersistAuthorizationActionUnderMachine() throws {
        let atmosphere = try listeningSource("Features/Listening/Views/ListeningAtmosphere.swift")
        XCTAssertTrue(atmosphere.contains("player.recoveryAction == .retryPlayback"))
        XCTAssertFalse(
            atmosphere.contains("player.recoveryAction ?? room.display.recoveryAction"),
            "Authorization and settings recovery must not remain as persistent actions below the CD machine"
        )
    }

    func testListenShelfUsesCompactHeaderWhenThereIsNoShowAllAction() throws {
        let shelf = try listeningSource("Features/Listening/Views/ListeningShelfView.swift")
        XCTAssertTrue(shelf.contains("compactHeaderHeight: CGFloat = 32"))
        XCTAssertTrue(shelf.contains("showsAllDiscs || dynamicTypeSize.isAccessibilitySize"))
    }

    func testRootPagesDoNotStackLegacyTabBarClearanceOnSafeAreaInset() throws {
        for path in [
            "Features/CurrentShow/CurrentShowManagementView.swift",
            "Features/Listening/Views/ListeningRoomView.swift",
            "Features/Listening/Views/ListeningPreparingView.swift",
            "Features/Footprints/FootprintDashboardView.swift",
            "Features/Footprints/FootprintsView.swift"
        ] {
            XCTAssertFalse(
                try listeningSource(path).contains("BSLayout.tabBarContentInset"),
                "\(path) must rely on the root safe-area inset instead of adding the old 96pt tab clearance"
            )
        }
    }

    func testCommittedProjectUsesAlreadyReferencedListeningSources() throws {
        let iosRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sourceRoot = iosRoot.appendingPathComponent("BeforeShow")
        let testsRoot = iosRoot.appendingPathComponent("BeforeShowTests")
        let project = try String(
            contentsOf: iosRoot.appendingPathComponent("BeforeShow.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("Features/Listening/Views/ListeningPolishedBottomChrome.swift").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: testsRoot.appendingPathComponent("ListeningMiniPlayerPlaybackAppearanceTests.swift").path
        ))
        XCTAssertTrue(project.contains("ListeningPolishedBottomChrome.swift in Sources"))
        XCTAssertTrue(project.contains("ListeningMiniPlayerPlaybackAppearanceTests.swift in Sources"))
        XCTAssertTrue(try listeningSource("Features/Listening/Views/ListeningPolishedBottomChrome.swift").contains("struct ListeningPolishedBottomChrome"))
        XCTAssertTrue(try String(contentsOf: testsRoot.appendingPathComponent("ListeningMiniPlayerPlaybackAppearanceTests.swift"), encoding: .utf8).contains("final class ListeningMiniPlayerPlaybackAppearanceTests"))
    }

    func testRootViewRemainsWithinArchitectureBudget() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("BeforeShow/RootView.swift"))
        XCTAssertLessThanOrEqual(data.count, 12_000)
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