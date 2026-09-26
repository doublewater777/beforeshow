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
            "仅提供歌曲信息", "授权后载入唱片", "放置唱片中…",
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

    func testAlwaysCompactGlassChromeContractsAreLockedInSource() throws {
        let listeningRoot = try listeningSource("Features/Listening/Views/ListeningPolishedBottomChrome.swift")
        let whitespaceInsensitiveListeningRoot = listeningRoot
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        XCTAssertTrue(
            listeningRoot.contains("GlassEffectContainer(spacing: ListeningBottomBarLayout.gap)"),
            "Nearby root controls must share one system glass sampling container"
        )
        XCTAssertTrue(
            listeningRoot.contains(".glassEffect(.regular.interactive(), in: Circle())"),
            "Side root controls must use the system interactive circular glass effect"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".glassEffect(.regular.interactive(), in: Capsule())").count - 1,
            1,
            "Listen must be one persistent interactive capsule whose equal width and height naturally form the collapsed circle"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".glassEffectID(\"listen\", in: glassNamespace)").count - 1,
            1,
            "Listen must keep one persistent glass identity instead of swapping two structural glass views"
        )
        XCTAssertFalse(
            listeningRoot.contains(".glassEffectTransition("),
            "The center shell must resize continuously rather than depending on insertion/removal glass transitions"
        )
        XCTAssertTrue(
            listeningRoot.contains("private enum ListeningBottomBarGeometry"),
            "Bottom Chrome selection targets must come from one deterministic geometry model"
        )
        XCTAssertTrue(
            whitespaceInsensitiveListeningRoot.contains("middleWidth=showsMiniPlayer?ListeningBottomBarLayout.miniPlayerWidth:ListeningBottomBarLayout.tabSize")
                && whitespaceInsensitiveListeningRoot.contains("return-sideDistance")
                && whitespaceInsensitiveListeningRoot.contains("returnsideDistance"),
            "The geometry model must derive symmetric side-tab centers from the actual middle-slot width"
        )
        XCTAssertFalse(
            listeningRoot.contains("PreferenceKey")
                || listeningRoot.contains(".anchorPreference(")
                || listeningRoot.contains(".backgroundPreferenceValue("),
            "Active selection must not wait for a second layout pass or preference propagation"
        )
        XCTAssertTrue(
            listeningRoot.contains("ZStack {\n                selectionLens")
                && whitespaceInsensitiveListeningRoot.contains(".offset(x:ListeningBottomBarGeometry.selectionOffset(for:selectedTab,showsMiniPlayer:showsMiniPlayer))")
                && whitespaceInsensitiveListeningRoot.contains(".animation(miniPlayerMorphAnimation,value:selectedTab)"),
            "One persistent non-layout lens must use the deterministic geometry model without participating in control layout"
        )
        XCTAssertTrue(
            listeningRoot.contains("private var miniPlayerMorphAnimation: Animation?")
                && whitespaceInsensitiveListeningRoot.contains("guard!reduceMotionelse{returnnil}")
                && whitespaceInsensitiveListeningRoot.contains("return.spring(response:0.28,dampingFraction:0.90)"),
            "Selection and mini-player geometry must share a reversible spring"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".accessibilityAddTraits(isSelected ? .isSelected : [])").count - 1,
            2,
            "Tab selection must update traits in place so the moving glass buttons retain structural identity"
        )
        XCTAssertTrue(
            listeningRoot.contains(".fill(BSColor.Stage.accent.opacity(0.16))"),
            "The active motion layer must be ordinary content sampled beneath the persistent Liquid Glass"
        )
        XCTAssertTrue(
            whitespaceInsensitiveListeningRoot.contains("privatefuncselectTab(_tab:BeforeShowTab){guardselectedTab!=tabelse{return}selectedTab=tab}"),
            "Navigation state must update directly instead of wrapping the TabView selection in a global animation transaction"
        )
        XCTAssertTrue(
            listeningRoot.contains("selectedTab: selectedTab,"),
            "Mini-player presentation must derive directly from the selected destination"
        )
        XCTAssertFalse(
            listeningRoot.contains("@State private var presentedTab")
                || listeningRoot.contains("@State private var centerShowsMiniPlayer")
                || listeningRoot.contains(".onChange(of: showsMiniPlayer)")
                || listeningRoot.contains("await Task.yield()")
                || listeningRoot.contains("ListeningBottomBarLayout.transitionDuration")
                || listeningRoot.contains(".smooth(duration:"),
            "Bottom Chrome motion must not depend on delayed or duplicated presentation state"
        )
        XCTAssertFalse(
            listeningRoot.contains("HStack(spacing: ListeningBottomBarLayout.gap)"),
            "Root-tab positions must not be coupled to the mini-player width through an animated HStack"
        )
        XCTAssertTrue(
            whitespaceInsensitiveListeningRoot.contains(".frame(width:ListeningBottomBarLayout.playerGroupWidth,height:ListeningBottomBarLayout.tabSize)"),
            "The GlassEffectContainer sampling footprint must stay fixed while the center control resizes"
        )
        XCTAssertTrue(
            whitespaceInsensitiveListeningRoot.contains("ifshowsMiniPlayer,letroom,lettrack")
                && whitespaceInsensitiveListeningRoot.contains("width:showsMiniPlayer?ListeningBottomBarLayout.miniPlayerWidth:ListeningBottomBarLayout.tabSize")
                && whitespaceInsensitiveListeningRoot.contains(".glassEffect(.regular.interactive(),in:Capsule())")
                && whitespaceInsensitiveListeningRoot.contains(".animation(miniPlayerMorphAnimation,value:showsMiniPlayer)"),
            "One persistent center shell must animate its own bounds from circle-sized to mini-player-sized"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".transition(.opacity)").count - 1,
            2,
            "Only the center content should crossfade while the glass shell itself remains persistent"
        )
        XCTAssertFalse(
            listeningRoot.contains("guard !reduceMotion, showsMiniPlayer")
                || listeningRoot.contains("guard !reduceMotion, selectedTab != .listen"),
            "Returning to Listen must not snap controls ahead of the shrinking player"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".animation(miniPlayerMorphAnimation, value: showsMiniPlayer)").count - 1,
            4,
            "Both side tabs, selection lens and center shell must share geometry timing"
        )
        XCTAssertTrue(
            listeningRoot.contains("private var miniPlayerMorphAnimation: Animation?")
                && whitespaceInsensitiveListeningRoot.contains("return.spring(response:0.28,dampingFraction:0.90)"),
            "The persistent center shell must use one reversible native spring in both directions"
        )
        XCTAssertTrue(
            listeningRoot.contains("private var centerContentAnimation: Animation")
                && whitespaceInsensitiveListeningRoot.contains(".easeOut(duration:reduceMotion?0.16:0.10)"),
            "Reduce Motion must keep a short content crossfade while suppressing the width spring"
        )
        XCTAssertTrue(
            listeningRoot.contains(".frame(height: ListeningBottomBarLayout.tabSize)"),
            "Root chrome must keep a constant vertical footprint while Listen changes width"
        )
        XCTAssertTrue(
            listeningRoot.contains("static let miniPlayerWidth: CGFloat = 216"),
            "Compact playback must have enough room for disc, track/artist metadata, and play/pause"
        )
        XCTAssertTrue(
            listeningRoot.contains("paused: reduceMotion || !showsPlayingState"),
            "Disc spin must pause when Reduce Motion is enabled"
        )
        XCTAssertTrue(listeningRoot.contains("\"listening.miniPlayer.playPause\""))
        XCTAssertTrue(
            listeningRoot.contains("Text(track.title)")
                && listeningRoot.contains("Text(track.artistName)"),
            "Expanded compact playback must show both track title and artist"
        )
        XCTAssertFalse(
            listeningRoot.contains("ListeningLegacyDetachedBottomChrome")
                || listeningRoot.contains("if #available(iOS 26.0, *)")
                || listeningRoot.contains("@available(iOS 26.0, *)"),
            "iOS 26-only Bottom Chrome must stay free of the legacy compatibility path"
        )
        XCTAssertFalse(
            listeningRoot.contains(".background(")
                || listeningRoot.contains("Material")
                || listeningRoot.contains("LinearGradient(")
                || listeningRoot.contains(".blur("),
            "Bottom Chrome must stay backgroundless without a Material panel, black gradient, or custom backdrop blur"
        )
        XCTAssertFalse(
            listeningRoot.contains("tabViewBottomAccessory")
                || listeningRoot.contains("tabViewBottomAccessoryPlacement")
                || listeningRoot.contains("tabBarMinimizeBehavior"),
            "The root must not fall back to the system expanded/text Tab Bar model"
        )
        XCTAssertFalse(
            listeningRoot.contains("matchedGeometryEffect"),
            "Ordinary matchedGeometryEffect must not drive the stable root layout"
        )
        XCTAssertFalse(
            listeningRoot.contains(".glassEffectID(\"active-tab\", in: glassNamespace)"),
            "Active selection motion must not add a second Liquid Glass identity on top of the three persistent controls"
        )
        XCTAssertFalse(
            listeningRoot.contains("Image(systemName: \"eject.fill\")"),
            "Global playback chrome must not expose the CD mechanism control"
        )
    }

    func testCurrentShowAmbientBackgroundCarriesCoverHueIntoLowerSafeArea() throws {
        let stage = try listeningSource("UI/DesignSystem/BSStagePresentation.swift")
        let ambientStart = try XCTUnwrap(stage.range(of: "struct CurrentShowAmbientBackground: View {"))
        let ambientEnd = try XCTUnwrap(stage.range(of: "\nstruct BSSurfacePanel", range: ambientStart.upperBound..<stage.endIndex))
        let ambient = String(stage[ambientStart.lowerBound..<ambientEnd.lowerBound])

        XCTAssertGreaterThanOrEqual(
            ambient.components(separatedBy: "ambientColor.opacity(").count - 1,
            4,
            "Current Show must keep separate cover-derived ambient contributions for upper and lower atmosphere"
        )
        XCTAssertGreaterThanOrEqual(
            ambient.components(separatedBy: "Ellipse()").count - 1,
            2,
            "Current Show must retain a distinct lower ambient glow rather than only the upper cover bloom"
        )
        XCTAssertTrue(ambient.contains(".ignoresSafeArea()"))

        let positionRegex = try NSRegularExpression(
            pattern: #"\.position\(x: geometry\.size\.width \* [0-9.]+, y: geometry\.size\.height \* ([0-9.]+)\)"#
        )
        let ambientNSString = ambient as NSString
        let positions = positionRegex.matches(
            in: ambient,
            range: NSRange(location: 0, length: ambientNSString.length)
        ).compactMap { match -> Double? in
            guard match.numberOfRanges > 1 else { return nil }
            return Double(ambientNSString.substring(with: match.range(at: 1)))
        }
        XCTAssertTrue(
            positions.contains(where: { $0 > 0.5 }),
            "At least one cover-derived ambient glow must live in the lower half so hue reaches the lower safe area"
        )

        let darkStopRegex = try NSRegularExpression(
            pattern: #"Color\.black\.opacity\(([0-9.]+)\), location: ([0-9.]+)"#
        )
        let darkStops = darkStopRegex.matches(
            in: ambient,
            range: NSRange(location: 0, length: ambientNSString.length)
        ).compactMap { match -> (opacity: Double, location: Double)? in
            guard match.numberOfRanges > 2 else { return nil }
            return (
                Double(ambientNSString.substring(with: match.range(at: 1))) ?? 0,
                Double(ambientNSString.substring(with: match.range(at: 2))) ?? 0
            )
        }
        let topDarkStop = try XCTUnwrap(darkStops.min(by: { $0.location < $1.location }))
        let bottomDarkStop = try XCTUnwrap(darkStops.max(by: { $0.location < $1.location }))
        XCTAssertGreaterThan(bottomDarkStop.location, 0.75)
        XCTAssertGreaterThan(
            bottomDarkStop.opacity,
            topDarkStop.opacity,
            "The vertical contrast scrim must become darker toward the bottom while leaving cover hue visible"
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

    func testRootUsesNativeIOS26SafeAreaBarAndSoftBottomScrollEdge() throws {
        let rootChrome = try listeningSource("Features/Listening/ListeningFeatureRootView.swift")
        let rootView = try listeningSource("RootView.swift")

        XCTAssertTrue(rootView.contains("ListeningRootChromeModifier(selectedTab: $selectedTab)"))
        XCTAssertTrue(rootChrome.contains(".safeAreaBar(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(rootChrome.contains(".scrollEdgeEffectStyle(.soft, for: .bottom)"))
        XCTAssertTrue(rootChrome.contains("ListeningPolishedBottomChrome(selectedTab: $selectedTab)"))
        XCTAssertFalse(rootChrome.contains(".safeAreaInset(edge: .bottom"))
        XCTAssertFalse(rootChrome.contains(".tabViewBottomAccessory"))
        XCTAssertFalse(rootChrome.contains(".tabBarMinimizeBehavior"))
    }

    func testRootDestinationsHideTheNativeSystemTabBar() throws {
        for path in [
            "Features/CurrentShow/CurrentShowSession.swift",
            "Features/Listening/ListeningFeatureRootView.swift",
            "Features/Footprints/FootprintsView.swift"
        ] {
            XCTAssertTrue(
                try listeningSource(path).contains(".toolbar(.hidden, for: .tabBar)"),
                "\(path) must hide the labeled system bar behind detached icon-only root controls"
            )
        }
    }

    func testListenStageDoesNotPersistAuthorizationActionUnderMachine() throws {
        let currentSong = try listeningSource("Features/Listening/Views/ListeningCurrentSong.swift")
        XCTAssertTrue(currentSong.contains("player.recoveryAction == .retryPlayback"))
        XCTAssertFalse(
            currentSong.contains("player.recoveryAction ?? room.display.recoveryAction"),
            "Authorization and settings recovery must not remain as persistent actions below the CD machine"
        )
    }

    func testListenShelfUsesCompactHeaderWhenThereIsNoShowAllAction() throws {
        let shelf = try listeningSource("Features/Listening/Views/ListeningShelfView.swift")
        XCTAssertTrue(shelf.contains("compactHeaderHeight: CGFloat = 32"))
        XCTAssertTrue(shelf.contains("actionHeaderHeight = BSLayout.minTouchTarget"))
        XCTAssertTrue(shelf.contains("showsAllDiscs ? actionHeaderHeight : compactHeaderHeight"))
    }

    func testCurrentShowScrollContentClearsRootBottomChrome() throws {
        let currentShow = try listeningSource("Features/CurrentShow/CurrentShowManagementView.swift")
        XCTAssertTrue(
            currentShow.contains(".padding(.bottom, BSLayout.tabBarContentInset)"),
            "Current Show must keep enough trailing scroll room for the follow-up card to clear Bottom Chrome"
        )
    }

    func testCompatibilityLayerDoesNotRewriteOtherRootPageSpacing() throws {
        for path in [
            "Features/Listening/Views/ListeningRoomView.swift",
            "Features/Listening/Views/ListeningPreparingView.swift",
            "Features/Footprints/FootprintDashboardView.swift",
            "Features/Footprints/FootprintsView.swift"
        ] {
            XCTAssertFalse(
                try listeningSource(path).contains("BSLayout.tabBarContentInset"),
                "\(path) must not gain compatibility-only bottom padding"
            )
        }
    }

    func testProjectDeploymentTargetIsIOS26AndBottomChromeNeedsNoAvailabilityGate() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectYAML = try String(
            contentsOf: iosRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: iosRoot.appendingPathComponent("BeforeShow.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(projectYAML.contains("iOS: \"26.0\""))
        XCTAssertFalse(projectYAML.contains("iOS: \"18.0\""))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 26.0;"))
        XCTAssertFalse(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))

        let chrome = try listeningSource("Features/Listening/Views/ListeningPolishedBottomChrome.swift")
        XCTAssertFalse(chrome.contains("if #available(iOS 26.0, *)"))
        XCTAssertFalse(chrome.contains("@available(iOS 26.0, *)"))
        XCTAssertFalse(chrome.contains("ListeningLegacyDetachedBottomChrome"))
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
