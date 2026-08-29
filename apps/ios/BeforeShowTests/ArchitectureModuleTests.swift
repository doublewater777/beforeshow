import Foundation
import XCTest
@testable import BeforeShow

/// Light coverage for architecture-deepening modules (A–F): snapshot seam,
/// end policy without a separate phase arg, cover lifecycle is in
/// `ShowCoverLifecycleTests`.
final class ArchitectureModuleTests: XCTestCase {
    func testHomeArrivalOnlyAnimatesForTheNewCurrentShow() {
        let addedShowID = UUID()

        XCTAssertTrue(
            CurrentShowHomeArrivalPolicy.shouldAnimate(
                newShowID: addedShowID,
                currentShowID: addedShowID
            )
        )
        XCTAssertFalse(
            CurrentShowHomeArrivalPolicy.shouldAnimate(
                newShowID: addedShowID,
                currentShowID: UUID()
            )
        )
        XCTAssertFalse(
            CurrentShowHomeArrivalPolicy.shouldAnimate(
                newShowID: addedShowID,
                currentShowID: nil
            )
        )
    }

    func testForegroundMediaMaintenanceRunsInitiallyAndAfterThrottleWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(ForegroundMediaMaintenancePolicy.shouldRun(lastRun: nil, now: now))
        XCTAssertFalse(
            ForegroundMediaMaintenancePolicy.shouldRun(
                lastRun: now.addingTimeInterval(-ForegroundMediaMaintenancePolicy.minimumInterval + 1),
                now: now
            )
        )
        XCTAssertTrue(
            ForegroundMediaMaintenancePolicy.shouldRun(
                lastRun: now.addingTimeInterval(-ForegroundMediaMaintenancePolicy.minimumInterval),
                now: now
            )
        )
    }

    func testHomeHeroSnapshotFoldsPhaseAndTimeState() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "快照现场", date: start, startTime: start)
        // Same calendar day, one hour before doors: kind is `.today`, phase folds to `.pre`.
        let before = start.addingTimeInterval(-3_600)
        let snapshot = HomeHeroSnapshot(show: show, now: before)

        XCTAssertEqual(snapshot.timeState.kind, .today)
        XCTAssertEqual(snapshot.phase, .pre)
        XCTAssertEqual(snapshot.now, before)

        let daysEarlier = start.addingTimeInterval(-3 * 86_400)
        let preSnapshot = HomeHeroSnapshot(show: show, now: daysEarlier)
        XCTAssertEqual(preSnapshot.timeState.kind, .before)
        XCTAssertEqual(preSnapshot.phase, .pre)
    }

    func testHomeHeroSnapshotInactiveWhenCanceled() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "取消现场", date: start, startTime: start)
        show.markCanceled()
        let snapshot = HomeHeroSnapshot(show: show, now: start)

        XCTAssertEqual(snapshot.timeState.kind, .canceled)
        XCTAssertEqual(snapshot.phase, .inactive)
    }

    func testEndPolicyDerivesPhaseInternally() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "可落幕", date: start, startTime: start)
        let afterEstimated = start.addingTimeInterval(5 * 3_600)
        let state = CurrentShowTimeState(show: show, now: afterEstimated)

        XCTAssertEqual(state.kind, .postShow)
        XCTAssertTrue(
            CurrentShowEndPolicy.canRecordEnd(show: show, timeState: state, now: afterEstimated)
        )
    }

    func testCountdownPresentationAsksBeforeAnnouncingUnconfirmedEnd() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "等待确认的现场", date: start, startTime: start)
        let state = CurrentShowTimeState(
            show: show,
            now: start.addingTimeInterval(5 * 3_600)
        )

        XCTAssertEqual(
            HomeCountdownPresentationPolicy.state(for: show, timeState: state, now: start.addingTimeInterval(5 * 3_600)),
            .askingEnd
        )
    }

    func testCountdownPresentationConfirmsOnlyWhenEndedAtExists() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "已经确认的现场", date: start, startTime: start)
        show.markEnded(at: start.addingTimeInterval(5 * 3_600))
        let now = start.addingTimeInterval(5 * 3_600 + 60)
        let state = CurrentShowTimeState(show: show, now: now)

        XCTAssertEqual(
            HomeCountdownPresentationPolicy.state(for: show, timeState: state, now: now),
            .confirmedEnded
        )
    }

    func testUnconfirmedEstimatedEndRequiresPostBoundaryWithoutEndedAt() {
        // 首页 / widget 共用:postShow・ended 且未确认 endedAt → 「待确认」,不宣布落幕。
        XCTAssertTrue(
            CurrentShowTimeState.isUnconfirmedEstimatedEnd(kind: .postShow, hasConfirmedEnd: false)
        )
        XCTAssertTrue(
            CurrentShowTimeState.isUnconfirmedEstimatedEnd(kind: .ended, hasConfirmedEnd: false)
        )
        // dayEnded 是多日循环内部态,不算未确认散场。
        XCTAssertFalse(
            CurrentShowTimeState.isUnconfirmedEstimatedEnd(kind: .dayEnded, hasConfirmedEnd: false)
        )
        XCTAssertFalse(
            CurrentShowTimeState.isUnconfirmedEstimatedEnd(kind: .postShow, hasConfirmedEnd: true)
        )
    }

    func testCountdownBoundaryAtExactly24HoursShowsClockNotOneDay() throws {
        // 与 widget 同一阈值:remaining == 86400 必须是小时文案,只有 > 86400 才是「1 天」。
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let atThreshold = try Show(
            name: "恰好一天",
            date: now.addingTimeInterval(86_400),
            startTime: now.addingTimeInterval(86_400)
        )
        let state = CurrentShowTimeState(show: atThreshold, now: now)
        guard case .countdownClock = HomeCountdownPresentationPolicy.state(for: atThreshold, timeState: state, now: now) else {
            return XCTFail("remaining == 24h 应显示小时文案,不是「1 天」")
        }

        let pastThreshold = try Show(
            name: "一天多一秒",
            date: now.addingTimeInterval(86_401),
            startTime: now.addingTimeInterval(86_401)
        )
        let pastState = CurrentShowTimeState(show: pastThreshold, now: now)
        XCTAssertEqual(
            HomeCountdownPresentationPolicy.state(for: pastThreshold, timeState: pastState, now: now),
            .countdownDays(1)
        )
    }

    func testCountdownCopyUsesHoursThenMinutes() {
        XCTAssertEqual(
            CountdownCopy.until(remainingSeconds: 5 * 3_600 + 59),
            BSLocalization.format("%lld 小时后", Int64(5))
        )
        XCTAssertEqual(
            CountdownCopy.until(remainingSeconds: 3_599),
            BSLocalization.format("%lld 分钟后", Int64(59))
        )
    }

    func testHomeStatusSaysStartingSoonBeforeTodayShow() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "今天开场", date: start, startTime: start)
        let now = start.addingTimeInterval(-3_600)
        let state = CurrentShowTimeState(show: show, now: now)

        XCTAssertEqual(
            HomeShowIdentityPresentation.statusText(for: state, now: now),
            BSLocalization.text("马上开场")
        )
    }

    func testHomeLiveStatusUsesStartedCopy() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "进行中的现场", date: start, startTime: start)
        let now = start.addingTimeInterval(3_600)
        let state = CurrentShowTimeState(show: show, now: now)

        XCTAssertEqual(
            HomeShowIdentityPresentation.statusText(for: state, now: now),
            BSLocalization.text("开场了")
        )
    }

    func testFollowUpPolicyExcludesCurrentAndPast() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let past = try Show(name: "过去", date: now.addingTimeInterval(-86_400), startTime: now.addingTimeInterval(-86_400))
        let current = try Show(name: "当前", date: now, startTime: now)
        let later = try Show(name: "之后", date: now.addingTimeInterval(86_400), startTime: now.addingTimeInterval(86_400))

        let result = CurrentShowFollowUpPolicy.laterShows(
            from: [past, current, later],
            excluding: current.id,
            now: now
        )
        XCTAssertEqual(result.map(\.name), ["之后"])
    }

    func testImportedDraftWithoutStartTimeStaysUnconfirmed() throws {
        // Import path must not auto-commit a fallback clock merely because a form appears.
        var draft = ShowDraft(
            name: "识别现场",
            date: Date(timeIntervalSince1970: 2_000_000_000),
            startTime: nil,
            source: .screenshotOCR,
            recognizedFields: [.name]
        )
        XCTAssertNil(draft.startTime)
        XCTAssertFalse(draft.recognizedFields.contains(.startTime))
        XCTAssertFalse(draft.hasValidEndTime())

        draft.startTime = Calendar.current.date(
            bySettingHour: 19,
            minute: 30,
            second: 0,
            of: draft.date
        )
        XCTAssertNotNil(draft.startTime)
        XCTAssertTrue(draft.hasValidEndTime())
    }

    func testDraftKeepsEditableVenueAddress() throws {
        var draft = ShowDraft(
            name: "可编辑地点",
            date: Date(timeIntervalSince1970: 2_000_000_000),
            startTime: Date(timeIntervalSince1970: 2_000_000_000),
            venueAddress: "旧地址",
            source: .manual
        )
        draft.venueAddress = "新地址 1 号"
        let show = try draft.makeShow()
        XCTAssertEqual(show.venueAddress, "新地址 1 号")
        XCTAssertEqual(
            MapDestinationQuery.make(
                venueAddress: show.venueAddress,
                venueName: show.venueName,
                city: show.city,
                showName: show.name
            ),
            "新地址 1 号"
        )
    }

    func testLinkCatalogIncludesLiveNationAndRejectsLookalikes() {
        XCTAssertEqual(
            ShowLinkPlatformCatalog.displayName(forHost: "www.livenation.cn"),
            "Live Nation"
        )
        XCTAssertEqual(
            ShowLinkPlatformCatalog.displayName(forHost: "www.livenation.co.uk"),
            "Live Nation"
        )
        XCTAssertEqual(
            ShowLinkPlatformCatalog.displayName(forHost: "livenation.app.link"),
            "Live Nation"
        )
        XCTAssertNil(
            ShowLinkPlatformCatalog.displayName(forHost: "livenation.com.evil.example")
        )
        XCTAssertTrue(ShowLinkPlatformCatalog.supportSummary.contains("Live Nation"))
    }

    func testRemoteLinkParserMapsUnsupportedBackendCode() async {
        let json = """
        {
            "ok": false,
            "error": {
                "code": "UNSUPPORTED_PLATFORM",
                "message": "Unsupported show link platform"
            }
        }
        """
        let service = RemoteShowLinkParsingService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: ArchitectureMockURLSession(data: Data(json.utf8))
            )
        )

        do {
            _ = try await service.parse(link: "https://example.com/show/123")
            XCTFail("Expected unsupported-source error")
        } catch {
            XCTAssertEqual(error as? ShowLinkParsingError, .unsupportedSource)
        }
    }

    func testRemoteLinkParserMapsNotAShowBackendCode() async {
        let json = """
        {
            "ok": false,
            "error": {
                "code": "NOT_A_SHOW",
                "message": "Damai item is merchandise, not a show"
            }
        }
        """
        let service = RemoteShowLinkParsingService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: ArchitectureMockURLSession(data: Data(json.utf8))
            )
        )

        do {
            _ = try await service.parse(link: "https://m.damai.cn/shows/item.html?itemId=1065385649255")
            XCTFail("Expected not-a-show error")
        } catch {
            XCTAssertEqual(error as? ShowLinkParsingError, .notAShow)
        }
    }
}

private struct ArchitectureMockURLSession: URLSessionProtocol {
    let data: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
