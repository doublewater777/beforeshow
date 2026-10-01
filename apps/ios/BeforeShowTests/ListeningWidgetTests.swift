import Foundation
import XCTest
@testable import BeforeShow

final class ListeningWidgetTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("listening-widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = tempDirectory
    }

    override func tearDownWithError() throws {
        WidgetSnapshotStore.overrideContainerURL = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testListeningSnapshotCodableRoundTrip() throws {
        let original = WidgetListeningSnapshot(
            showID: UUID(),
            showName: "夜航西飞巡演",
            artistName: "回春丹",
            discTitle: "热门合辑 01",
            trackTitle: "艾蜜莉",
            coverImageURL: "https://example.com/cover.jpg",
            trackCount: 12,
            isPlaying: true,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetListeningSnapshot.self, from: data)

        XCTAssertEqual(original.showID, decoded.showID)
        XCTAssertEqual(original.showName, decoded.showName)
        XCTAssertEqual(original.artistName, decoded.artistName)
        XCTAssertEqual(original.discTitle, decoded.discTitle)
        XCTAssertEqual(original.trackTitle, decoded.trackTitle)
        XCTAssertEqual(original.coverImageURL, decoded.coverImageURL)
        XCTAssertEqual(original.trackCount, decoded.trackCount)
        XCTAssertEqual(original.isPlaying, decoded.isPlaying)
        XCTAssertTrue(original.isContentEqual(to: decoded))
    }

    func testListeningSnapshotContentEqualityIgnoresGeneratedAt() {
        let baseID = UUID()
        let snap1 = WidgetListeningSnapshot(
            showID: baseID,
            showName: "测试演出",
            artistName: "艺人A",
            discTitle: "合辑 01",
            trackTitle: "歌曲 1",
            coverImageURL: nil,
            trackCount: 10,
            isPlaying: false,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let snap2 = WidgetListeningSnapshot(
            showID: baseID,
            showName: "测试演出",
            artistName: "艺人A",
            discTitle: "合辑 01",
            trackTitle: "歌曲 1",
            coverImageURL: nil,
            trackCount: 10,
            isPlaying: false,
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertTrue(snap1.isContentEqual(to: snap2))

        var snap3 = snap2
        snap3.isPlaying = true
        XCTAssertFalse(snap1.isContentEqual(to: snap3))
    }

    func testWidgetListeningStoreWriteReadAndClear() {
        XCTAssertNil(WidgetListeningStore.read())

        let snapshot = WidgetListeningSnapshot(
            showID: UUID(),
            showName: "草莓音乐节",
            artistName: "万能青年旅店",
            discTitle: "冀西南林路行",
            trackTitle: "山雀",
            coverImageURL: nil,
            trackCount: 8,
            isPlaying: false,
            generatedAt: Date()
        )

        XCTAssertTrue(WidgetListeningStore.write(snapshot))
        let readBack = WidgetListeningStore.read()
        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack?.showName, "草莓音乐节")
        XCTAssertEqual(readBack?.trackTitle, "山雀")

        XCTAssertTrue(WidgetListeningStore.write(nil))
        XCTAssertNil(WidgetListeningStore.read())
    }

    func testWidgetListeningStoreFallbackFromShowSnapshot() throws {
        // 当尚无听歌快照但存在当前现场快照时，应自动降级生成现场预习快照
        let timing = ShowTimingFields(
            date: Date(),
            startTime: Date(),
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let showSnapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "安溥「炼云」演唱会",
            city: "台北",
            venueName: "小巨蛋",
            coverImageURL: "https://example.com/anpu.jpg",
            timing: timing,
            generatedAt: Date()
        )
        WidgetSnapshotStore.write(showSnapshot)

        let fallback = WidgetListeningStore.read()
        XCTAssertNotNil(fallback)
        XCTAssertEqual(fallback?.showID, showSnapshot.showID)
        XCTAssertEqual(fallback?.showName, "安溥「炼云」演唱会")
        XCTAssertEqual(fallback?.coverImageURL, "https://example.com/anpu.jpg")
        XCTAssertFalse(fallback?.isPlaying ?? true)
    }

    @MainActor
    func testListeningIntentBridgeInvocation() async {
        final class MockIntentHandler: ListeningIntentHandling {
            var toggleCallCount = 0
            var skipNextCallCount = 0
            var skipPreviousCallCount = 0

            func togglePlayPause() async { toggleCallCount += 1 }
            func skipToNext() async { skipNextCallCount += 1 }
            func skipToPrevious() async { skipPreviousCallCount += 1 }
        }

        let mock = MockIntentHandler()
        ListeningIntentBridge.handler = mock

        await ListeningIntentBridge.performTogglePlayPause()
        XCTAssertEqual(mock.toggleCallCount, 1)

        await ListeningIntentBridge.performSkipToNext()
        XCTAssertEqual(mock.skipNextCallCount, 1)

        await ListeningIntentBridge.performSkipToPrevious()
        XCTAssertEqual(mock.skipPreviousCallCount, 1)
    }

    func testListeningWidgetKindsRegistered() {
        XCTAssertTrue(BeforeShowWidgetKind.all.contains(BeforeShowWidgetKind.homeListening))
        XCTAssertTrue(BeforeShowWidgetKind.all.contains(BeforeShowWidgetKind.lockScreenListening))
        XCTAssertTrue(BeforeShowWidgetKind.all.contains(BeforeShowWidgetKind.homeCabinet))
        XCTAssertEqual(BeforeShowWidgetKind.homeListening, "BeforeShowListeningWidget")
        XCTAssertEqual(BeforeShowWidgetKind.lockScreenListening, "BeforeShowLockScreenListeningWidget")
        XCTAssertEqual(BeforeShowWidgetKind.homeCabinet, "BeforeShowCabinetWidget")
    }

    func testCabinetDiscItemCodableAndWidgetKind() throws {
        let disc = WidgetCabinetDiscItem(
            id: "disc-01",
            title: "热门合辑 01",
            artistName: "回春丹",
            coverImageURL: "https://example.com/cover.jpg",
            trackCount: 12,
            isLoaded: true
        )
        let data = try JSONEncoder().encode(disc)
        let decoded = try JSONDecoder().decode(WidgetCabinetDiscItem.self, from: data)
        XCTAssertEqual(disc, decoded)
    }

    func testFallbackPopulatesCabinetDiscs() {
        let timing = ShowTimingFields(
            date: Date(),
            startTime: Date(),
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let showSnapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "告五人「宇宙的有趣」巡演",
            city: "杭州",
            venueName: "奥体中心",
            coverImageURL: "https://example.com/accusefive.jpg",
            timing: timing,
            generatedAt: Date()
        )
        WidgetSnapshotStore.write(showSnapshot)

        let fallback = WidgetListeningStore.read()
        XCTAssertNotNil(fallback)
        XCTAssertEqual(fallback?.cabinetDiscs.count, 3)
        XCTAssertEqual(fallback?.cabinetDiscs.first?.title, "热门合辑 01")
    }
}
