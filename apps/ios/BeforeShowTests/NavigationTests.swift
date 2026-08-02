import Foundation
import XCTest
@testable import BeforeShow

final class NavigationTests: XCTestCase {
    func testTabEnumExposesMainProductSurfaces() {
        let tabs = BeforeShowTab.allCases
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs, [.current, .footprints])
    }

    func testTabRawValuesAndLabelsUseCorrectDomainLanguage() {
        XCTAssertEqual(BeforeShowTab.current.rawValue, "当前")
        XCTAssertEqual(BeforeShowTab.footprints.rawValue, "足迹")
    }

    /// 设置不是主导航项；当前现场主海报也不承载溢出菜单。
    func testSettingsIsNotAMainTab() {
        XCTAssertFalse(BeforeShowTab.allCases.contains { $0.rawValue == "设置" })
    }

    func testTabLabelsDoNotUseForbiddenTerms() {
        let forbiddenTerms = ["行程", "歌单", "余韵", "主演出", "演出列表", "日程"]

        for tab in BeforeShowTab.allCases {
            let label = tab.rawValue
            for term in forbiddenTerms {
                XCTAssertFalse(label.contains(term), "Tab label '\(label)' should not contain forbidden term '\(term)'")
            }
        }
    }
    func testCurrentShowQuickActionsAreAlwaysVisible() {
        XCTAssertEqual(
            CurrentShowQuickAction.visibleActions,
            [.route, .companion]
        )
    }

    func testCurrentFollowUpsExcludeCurrentPastChangedAndSortAscending() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let current = try Show(name: "当前", date: now, startTime: now)
        let later = try Show(name: "较晚", date: now.addingTimeInterval(8_000), startTime: now.addingTimeInterval(8_000))
        let sooner = try Show(name: "较近", date: now.addingTimeInterval(4_000), startTime: now.addingTimeInterval(4_000))
        let past = try Show(name: "过去", date: now.addingTimeInterval(-4_000), startTime: now.addingTimeInterval(-4_000))
        let canceled = try Show(name: "取消", date: now.addingTimeInterval(2_000), startTime: now.addingTimeInterval(2_000))
        canceled.markCanceled()

        let result = CurrentShowFollowUpPolicy.laterShows(
            from: [later, current, canceled, past, sooner],
            excluding: current.id,
            now: now
        )

        XCTAssertEqual(result.map(\.name), ["较近", "较晚"])
    }

    func testCurrentFollowUpsDropShowAfterItsStartTimePasses() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "即将开场",
            date: now.addingTimeInterval(60),
            startTime: now.addingTimeInterval(60)
        )

        XCTAssertEqual(
            CurrentShowFollowUpPolicy.laterShows(from: [show], excluding: nil, now: now).map(\.id),
            [show.id]
        )
        XCTAssertTrue(
            CurrentShowFollowUpPolicy.laterShows(
                from: [show],
                excluding: nil,
                now: now.addingTimeInterval(61)
            ).isEmpty
        )
    }

    func testEstimatedEndOffersBackfillUntilRealEndIsConfirmed() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "超时现场", date: start, startTime: start)
        let afterEstimatedEnd = start.addingTimeInterval(5 * 3_600)
        let timeState = CurrentShowTimeState(show: show, now: afterEstimatedEnd)
        let phase = HomeShowPhase(timeState: timeState, now: afterEstimatedEnd)

        XCTAssertEqual(timeState.kind, .postShow)
        XCTAssertEqual(
            HomeCountdownLockup.endActionTitle(
                phase: phase,
                timeState: timeState,
                hasConfirmedEnd: false
            ),
            "补记真实散场时间"
        )
        XCTAssertNil(
            HomeCountdownLockup.endActionTitle(
                phase: phase,
                timeState: timeState,
                hasConfirmedEnd: true
            )
        )
    }

    func testMultiDayDailyCycleCannotBeEndedOnAnIntermediateLiveDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 7, day: 8, hour: 19, minute: 0, calendar: calendar)
        let endDate = makeDate(year: 2026, month: 7, day: 10, hour: 0, minute: 0, calendar: calendar)
        let dailyEnd = makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 0, calendar: calendar)
        let show = try Show(name: "三日音乐节", date: start, startTime: start, endDate: endDate, endTime: dailyEnd)
        let middleDay = makeDate(year: 2026, month: 7, day: 9, hour: 20, minute: 0, calendar: calendar)
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: middleDay)
        let phase = HomeShowPhase(timeState: state, now: middleDay)

        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(phase, .live)
        XCTAssertFalse(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: state, now: middleDay, calendar: calendar))

        let finalDay = makeDate(year: 2026, month: 7, day: 10, hour: 20, minute: 0, calendar: calendar)
        let finalState = CurrentShowTimeState(show: show, calendar: calendar, now: finalDay)
        let finalPhase = HomeShowPhase(timeState: finalState, now: finalDay)
        XCTAssertEqual(finalPhase, .live)
        XCTAssertTrue(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: finalState, now: finalDay, calendar: calendar))
    }

    func testFinalOvernightDailyCycleRemainsLiveAfterMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar)
        let endDate = makeDate(year: 2026, month: 8, day: 10, hour: 0, minute: 0, calendar: calendar)
        let dailyEnd = makeDate(year: 2026, month: 8, day: 8, hour: 1, minute: 0, calendar: calendar)
        let show = try Show(name: "跨午夜音乐节", date: start, startTime: start, endDate: endDate, endTime: dailyEnd)
        let finalOvernight = makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 30, calendar: calendar)
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: finalOvernight)
        let phase = HomeShowPhase(timeState: state, now: finalOvernight)

        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(phase, .live)
        XCTAssertTrue(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: state, now: finalOvernight, calendar: calendar))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute).date!
    }

}

/// Widget / Live Activity 回归测试放在已纳入 Xcode test target 的源文件中。
/// 工程由 XcodeGen 管理，但 CI 直接使用已提交的 xcodeproj，因此不能只新增未引用文件。
final class WidgetRuntimeRegressionTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-runtime-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = tempDirectory
    }

    override func tearDownWithError() throws {
        WidgetSnapshotStore.overrideContainerURL = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testPruneWithoutCurrentSourceDeletesAllHashedCovers() throws {
        let cachedFiles = [
            "cover-old.jpg",
            "cover-old-la.jpg",
            "cover-old.jpg.source",
        ]
        for filename in cachedFiles {
            try Data("cached".utf8).write(to: tempDirectory.appendingPathComponent(filename))
        }
        let unrelated = tempDirectory.appendingPathComponent("current-show.json")
        try Data("snapshot".utf8).write(to: unrelated)

        WidgetCoverCache.pruneCovers(except: nil)

        for filename in cachedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be removed"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testPruneKeepsOnlyCurrentSourceCoverFiles() throws {
        let currentSource = "https://cdn.example.com/current.jpg"
        let previousSource = "https://cdn.example.com/previous.jpg"
        let currentFiles = [
            WidgetCoverCache.filename(for: currentSource),
            WidgetCoverCache.liveActivityFilename(for: currentSource),
            WidgetCoverCache.filename(for: currentSource) + ".source",
        ]
        let previousFiles = [
            WidgetCoverCache.filename(for: previousSource),
            WidgetCoverCache.liveActivityFilename(for: previousSource),
            WidgetCoverCache.filename(for: previousSource) + ".source",
        ]

        for filename in currentFiles + previousFiles {
            try Data("cached".utf8).write(to: tempDirectory.appendingPathComponent(filename))
        }

        WidgetCoverCache.pruneCovers(except: currentSource)

        for filename in currentFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be kept"
            )
        }
        for filename in previousFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be removed"
            )
        }
    }

    private func makeState(
        name: String = "测试现场",
        startOffset: TimeInterval = 0
    ) -> ShowLiveActivityAttributes.ContentState {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + startOffset)
        return ShowLiveActivityAttributes.ContentState(
            showName: name,
            city: "上海",
            venueName: "测试场馆",
            startDate: start,
            endDate: start.addingTimeInterval(4 * 3_600),
            coverImageFilename: nil
        )
    }

    func testPendingKeeperChoosesOnlyOneOfDuplicateExactMatches() {
        let desired = makeState()
        let records = [
            LiveActivityRuntimeRecord(
                id: "pending-1",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "pending-2",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "other-show",
                showID: "show-2",
                isPending: true,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.pendingKeeperID(
                in: records,
                showID: "show-1",
                state: desired
            ),
            "pending-1"
        )
    }

    func testPendingKeeperReturnsNilWhenOnlyStalePendingExists() {
        let desired = makeState()
        let stale = makeState(startOffset: 3_600)
        let records = [
            LiveActivityRuntimeRecord(
                id: "stale-pending",
                showID: "show-1",
                isPending: true,
                state: stale
            ),
            LiveActivityRuntimeRecord(
                id: "active-exact",
                showID: "show-1",
                isPending: false,
                state: desired
            ),
        ]

        XCTAssertNil(
            LiveActivityRuntimeSelection.pendingKeeperID(
                in: records,
                showID: "show-1",
                state: desired
            )
        )
    }

    func testDuplicateKeeperPrefersExactActiveOverExactPending() {
        let desired = makeState()
        let records = [
            LiveActivityRuntimeRecord(
                id: "pending-exact",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "active-exact",
                showID: "show-1",
                isPending: false,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: desired
            ),
            "active-exact"
        )
    }

    func testDuplicateKeeperPrefersExactPendingOverStaleActive() {
        let desired = makeState()
        let stale = makeState(startOffset: 3_600)
        let records = [
            LiveActivityRuntimeRecord(
                id: "active-stale",
                showID: "show-1",
                isPending: false,
                state: stale
            ),
            LiveActivityRuntimeRecord(
                id: "pending-exact",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: desired
            ),
            "pending-exact"
        )
    }

    func testDuplicateKeeperFallsBackToFirstMatchingShow() {
        let first = makeState(name: "旧内容")
        let second = makeState(name: "另一旧内容")
        let records = [
            LiveActivityRuntimeRecord(
                id: "other-show",
                showID: "show-2",
                isPending: false,
                state: first
            ),
            LiveActivityRuntimeRecord(
                id: "first-show-1",
                showID: "show-1",
                isPending: false,
                state: first
            ),
            LiveActivityRuntimeRecord(
                id: "second-show-1",
                showID: "show-1",
                isPending: true,
                state: second
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: makeState(name: "不存在")
            ),
            "first-show-1"
        )
    }
}
