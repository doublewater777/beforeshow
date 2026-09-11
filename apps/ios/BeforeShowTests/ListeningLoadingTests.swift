import XCTest
import SwiftUI
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningLoadingTests: XCTestCase {
    func testKnownAuthorizationIsPublishedBeforeArtistLookupFinishes() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: LoadingArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        let task = Task { await room.load(show: show) }
        defer { task.cancel(); room.mechanism.motion.stop() }
        try await wait { room.initialLoaded }
        XCTAssertEqual(room.access.authorizationStatus, .authorized)
        XCTAssertFalse(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .connecting)
        XCTAssertNil(room.display.recoveryAction)
        XCTAssertFalse(room.discs.isEmpty, "Cached records should remain browsable during access lookup")
    }

    func testRefreshKeepsResolvedPlaybackModeAndCachedDiscs() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let ids = room.discs.map(\.id)
        let refresh = Task { await room.load(show: show, force: true) }
        defer { refresh.cancel(); room.mechanism.motion.stop() }
        await Task.yield()
        XCTAssertTrue(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
        XCTAssertEqual(room.discs.map(\.id), ids)
        await refresh.value
    }

    func testPlayerPositionAcrossColdLaunchAuthorizationAndCatalogArrival() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let fixture = try ListeningDebugFixtures(scenario: .authorizationFlow)
            let context = fixture.container.mainContext
            let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
            let room = ListeningRoomCoordinator(
                context: context,
                catalogService: ListeningFixtureCatalog(scenario: .authorizationFlow),
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { _ in ListeningFixturePlayer() }
            )
            let probe = ListeningLayoutProbe()
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            func content(_ view: some View) -> AnyView {
                AnyView(view.environment(\.dynamicTypeSize, size)
                    .transaction { $0.disablesAnimations = true }
                    .onPreferenceChange(ListeningFramesKey.self) { probe.frames = $0 })
            }
            let host = UIHostingController(rootView: content(ListeningPreparingView(show: show)))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            defer { window.isHidden = true; room.mechanism.motion.stop() }
            try await wait { host.view.layoutIfNeeded(); return probe.frames["stage"] != nil }
            let coldStage = try XCTUnwrap(probe.frames["stage"])
            let coldCabinet = try XCTUnwrap(probe.frames["cabinet"])

            await room.load(show: show)
            XCTAssertEqual(room.presentation, .needsAuthorization)
            host.rootView = content(ListeningRoomView(room: room, show: show))
            try await settleLayout(host.view)
            assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)

            let authorization = Task { await room.authorize() }
            defer { authorization.cancel() }
            try await wait { room.isAuthorizing }
            try await settleLayout(host.view)
            XCTAssertEqual(room.display.roomMode, .connecting)
            XCTAssertNil(room.display.recoveryAction)
            assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)

            await authorization.value
            XCTAssertFalse(room.libraryDiscs.isEmpty)
            XCTAssertEqual(room.display.roomMode, .fullPlayback)
            try await settleLayout(host.view)
            assertFrames(probe.frames, stage: coldStage, cabinet: coldCabinet)
        }
    }

    func testEmptyShelfStatusHeightsMatchInAllSupportedLanguages() {
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            for locale in ["zh-Hans", "zh-Hant", "en"] {
                let bundle = Bundle(path: Bundle.main.path(forResource: locale, ofType: "lproj")!)!
                func text(_ key: String, table: String? = nil) -> String { bundle.localizedString(forKey: key, value: key, table: table) }
                let variants = [
                    ListeningCatalogStatusView(title: "Connecting…", isLoading: true),
                    ListeningCatalogStatusView(title: text("连接 Apple Music"), subtitle: text("授权后载入唱片", table: "Listening"), actionTitle: "Authorize now"),
                    ListeningCatalogStatusView(title: text("连接 Apple Music"), subtitle: text("请在系统设置中允许访问 Apple Music"), actionTitle: "Open Settings"),
                    ListeningCatalogStatusView(title: text("正在检索与整理专场唱片…"), isLoading: true),
                    ListeningCatalogStatusView(title: text("暂时无法载入音乐"), actionTitle: "Retry")
                ]
                let heights = variants.map { status in
                    let host = UIHostingController(rootView: ListeningShelfView(title: "Popular Mix", count: "0") {
                        status
                    }.environment(\.dynamicTypeSize, size))
                    return host.sizeThatFits(in: CGSize(width: 362, height: 1000)).height
                }
                XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1, "\(locale), \(size): \(heights)")
            }
        }
    }

    private func assertFrames(_ frames: [String: CGRect], stage: CGRect, cabinet: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frames["stage"]?.minY ?? -1, stage.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frames["cabinet"]?.height ?? -1, cabinet.height, accuracy: 1, file: file, line: line)
    }

    private func settleLayout(_ view: UIView) async throws {
        for _ in 0..<8 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Loading state did not arrive")
    }
}

@MainActor
private final class ListeningLayoutProbe {
    var frames: [String: CGRect] = [:]
}

private struct LoadingArtistSearch: ArtistSearchServicing {
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        try await Task.sleep(for: .seconds(5))
        return []
    }
}
