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
            "Icon-only root controls must use the system interactive circular glass effect"
        )
        XCTAssertTrue(
            listeningRoot.contains(".glassEffect(.regular.interactive(), in: Capsule())"),
            "The compact playback control must use the system capsule glass effect"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".glassEffectID(\"listen\", in: glassNamespace)").count - 1,
            2,
            "Both collapsed Listen and compact playback must keep the same glass identity"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)").count - 1,
            2,
            "Both Listen states must use matched glass geometry normally and identity under Reduce Motion"
        )
        XCTAssertTrue(
            listeningRoot.contains("selectedTab: selectedTab,"),
            "Mini-player presentation must derive directly from the selected destination"
        )
        XCTAssertFalse(
            listeningRoot.contains("@State private var presentedTab")
                || listeningRoot.contains("await Task.yield()")
                || listeningRoot.contains("ListeningBottomBarLayout.transitionDuration")
                || listeningRoot.contains(".smooth(duration:"),
            "Phase 2 must remove delayed duplicate tab presentation and fixed-duration morph choreography"
        )
        XCTAssertTrue(
            whitespaceInsensitiveListeningRoot.contains(".animation(reduceMotion?nil:.spring("),
            "Normal Liquid Glass morphing must use a native spring instead of a fixed-duration animation"
        )
        XCTAssertEqual(
            listeningRoot.components(separatedBy: ".transition(reduceMotion ? .opacity.animation(.easeOut(duration: 0.16)) : .identity)").count - 1,
            2,
            "Both Listen states must use the same short Reduce Motion crossfade"
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
            "Ordinary matchedGeometryEffect must not drive the glass morph"
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

    func testCompatibilityLayerDoesNotRewriteRootPageSpacing() throws {
        for path in [
            "Features/CurrentShow/CurrentShowManagementView.swift",
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