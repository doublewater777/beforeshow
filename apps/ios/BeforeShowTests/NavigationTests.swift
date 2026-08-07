import Foundation
import SwiftData
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
            [.route, .companion, .ticket, .timetable, .memoryFragments]
        )
    }

    func testAssetSheetUsesDetailVisibilityHandoff() {
        XCTAssertTrue(
            DetailVisibilityHandoff.tabBarHidden(after: .assetSheetPresented)
        )
        XCTAssertFalse(
            DetailVisibilityHandoff.tabBarHidden(after: .assetSheetDismissed)
        )
    }

    func testCanceledAndEndedShowsKeepAssetManagementEntries() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let canceled = try Show(
            name: "已取消现场",
            date: now,
            startTime: now,
            changeStatus: .canceled
        )
        let ended = try Show(
            name: "已结束现场",
            date: now.addingTimeInterval(-3_600),
            startTime: now.addingTimeInterval(-3_600),
            endedAt: now
        )

        for show in [canceled, ended] {
            let entries = ShowAssetManagementPolicy.entries(for: show, assets: [])
            XCTAssertEqual(entries.map(\.kind), ShowAssetKind.allCases)
            XCTAssertEqual(entries.map(\.hasSavedAsset), [false, false])
        }
    }

    func testCompanionLifecyclePersistsNameAndSupportsRetry() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)

        XCTAssertEqual(show.companionStatus, .none)
        XCTAssertNil(show.companionName)

        try show.markCompanionInvitationSent(name: "  林嘉  ")
        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertEqual(show.companionName, "林嘉")

        try show.markCompanionConfirmed(name: show.companionName)
        XCTAssertEqual(show.companionStatus, .confirmed)

        try show.cancelCompanion()
        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertEqual(show.companionName, "林嘉")

        try show.markCompanionInvitationSent(name: "")
        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertNil(show.companionName)
    }

    func testCompanionLifecycleRejectsInvalidTransitions() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)

        XCTAssertThrowsError(try show.markCompanionConfirmed(name: "林嘉")) { error in
            XCTAssertEqual(
                error as? ShowCompanionMutationError,
                .invalidTransition(from: .none, to: .confirmed)
            )
        }
        XCTAssertEqual(show.companionStatus, .none)

        XCTAssertThrowsError(try show.cancelCompanion()) { error in
            XCTAssertEqual(
                error as? ShowCompanionMutationError,
                .invalidTransition(from: .none, to: .canceled)
            )
        }

        try show.markCompanionInvitationSent(name: "林嘉")
        XCTAssertThrowsError(try show.markCompanionInvitationSent(name: "重发")) { error in
            XCTAssertEqual(
                error as? ShowCompanionMutationError,
                .invalidTransition(from: .pending, to: .pending)
            )
        }
        XCTAssertEqual(show.companionName, "林嘉")

        try show.markCompanionConfirmed(name: "林嘉")
        XCTAssertThrowsError(try show.markCompanionInvitationSent(name: "旁路")) { error in
            XCTAssertEqual(
                error as? ShowCompanionMutationError,
                .invalidTransition(from: .confirmed, to: .pending)
            )
        }
        XCTAssertEqual(show.companionStatus, .confirmed)
    }

    func testCompanionStateCanBeRestoredAfterCanceledShare() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        let snapshot = show.companionStateSnapshot()

        try show.markCompanionInvitationSent(name: "林嘉")
        XCTAssertEqual(show.companionStatus, .pending)

        show.restoreCompanionState(status: snapshot.status, name: snapshot.name)
        XCTAssertEqual(show.companionStatus, .none)
        XCTAssertNil(show.companionName)
    }

    func testUnnamedConfirmedCompanionsDoNotMergeAcrossShows() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showA = try Show(name: "A", date: now, startTime: now)
        try showA.markCompanionInvitationSent(name: nil)
        try showA.markCompanionConfirmed(name: nil)
        showA.markEnded(at: now)

        let showB = try Show(name: "B", date: now.addingTimeInterval(3_600), startTime: now.addingTimeInterval(3_600))
        try showB.markCompanionInvitationSent(name: nil)
        try showB.markCompanionConfirmed(name: nil)
        showB.markEnded(at: now.addingTimeInterval(3_600))

        let history = CompanionSharedHistory.shows(matching: showA, from: [showA, showB])
        XCTAssertEqual(history.map(\.id), [showA.id])
    }

    func testNamedConfirmedCompanionsMergeAcrossEndedShows() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showA = try Show(name: "A", date: now, startTime: now)
        try showA.markCompanionInvitationSent(name: "林嘉")
        try showA.markCompanionConfirmed(name: "林嘉")
        showA.markEnded(at: now)

        let showB = try Show(name: "B", date: now.addingTimeInterval(3_600), startTime: now.addingTimeInterval(3_600))
        try showB.markCompanionInvitationSent(name: "林嘉")
        try showB.markCompanionConfirmed(name: "林嘉")
        showB.markEnded(at: now.addingTimeInterval(3_600))

        let other = try Show(name: "C", date: now.addingTimeInterval(7_200), startTime: now.addingTimeInterval(7_200))
        try other.markCompanionInvitationSent(name: "小雨")
        try other.markCompanionConfirmed(name: "小雨")
        other.markEnded(at: now.addingTimeInterval(7_200))

        let history = CompanionSharedHistory.shows(matching: showB, from: [showA, showB, other])
        XCTAssertEqual(history.map(\.id), [showB.id, showA.id])
    }

    @MainActor
    func testConfirmedCompanionSurvivesModelContextReload() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        container.mainContext.insert(show)
        try show.markCompanionInvitationSent(name: "林嘉")
        try show.markCompanionConfirmed(name: "林嘉")
        try container.mainContext.save()

        let reloadedContext = ModelContext(container)
        let reloaded = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(reloaded.companionStatus, .confirmed)
        XCTAssertEqual(reloaded.companionName, "林嘉")
    }

    @MainActor
    func testPendingAndCanceledCompanionSurviveModelContextReload() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let pending = try Show(name: "待确认", date: now, startTime: now)
        try pending.markCompanionInvitationSent(name: "林嘉")
        container.mainContext.insert(pending)

        let canceled = try Show(name: "已取消", date: now.addingTimeInterval(60), startTime: now.addingTimeInterval(60))
        try canceled.markCompanionInvitationSent(name: "小雨")
        try canceled.cancelCompanion()
        container.mainContext.insert(canceled)
        try container.mainContext.save()

        let reloadedContext = ModelContext(container)
        let reloaded = try reloadedContext.fetch(FetchDescriptor<Show>())
        let reloadedPending = try XCTUnwrap(reloaded.first { $0.name == "待确认" })
        let reloadedCanceled = try XCTUnwrap(reloaded.first { $0.name == "已取消" })
        XCTAssertEqual(reloadedPending.companionStatus, .pending)
        XCTAssertEqual(reloadedPending.companionName, "林嘉")
        XCTAssertEqual(reloadedCanceled.companionStatus, .canceled)
        XCTAssertEqual(reloadedCanceled.companionName, "小雨")
    }

    func testCompanionQuickActionReflectsEveryPrototypeState() {
        let none = CompanionQuickActionPresentation(status: .none, companionName: nil, isEnded: false)
        XCTAssertEqual(none.title, "同行")
        XCTAssertEqual(none.accessibilityLabel, "同行，邀请一位朋友")
        XCTAssertFalse(none.showsPendingIndicator)
        XCTAssertFalse(none.showsAvatars)
        XCTAssertNil(none.companionName)

        let pending = CompanionQuickActionPresentation(status: .pending, companionName: "林嘉", isEnded: false)
        XCTAssertEqual(pending.title, "待确认")
        XCTAssertEqual(pending.accessibilityLabel, "同行，等待林嘉确认")
        XCTAssertTrue(pending.showsPendingIndicator)
        XCTAssertFalse(pending.showsAvatars)

        let confirmed = CompanionQuickActionPresentation(status: .confirmed, companionName: "林嘉", isEnded: false)
        XCTAssertEqual(confirmed.title, "与林嘉")
        XCTAssertEqual(confirmed.accessibilityLabel, "同行，与林嘉已确认")
        XCTAssertEqual(confirmed.companionName, "林嘉")
        XCTAssertFalse(confirmed.showsPendingIndicator)
        XCTAssertTrue(confirmed.showsAvatars)

        let ended = CompanionQuickActionPresentation(status: .confirmed, companionName: "林嘉", isEnded: true)
        XCTAssertEqual(ended.title, "共同足迹")
        XCTAssertEqual(ended.accessibilityLabel, "同行，与林嘉的共同足迹")
        XCTAssertTrue(ended.showsAvatars)
        XCTAssertEqual(ended.companionName, "林嘉")

        let namedWithYu = CompanionQuickActionPresentation(status: .confirmed, companionName: "与田", isEnded: false)
        XCTAssertEqual(namedWithYu.title, "与与田")
        XCTAssertEqual(namedWithYu.companionName, "与田")

        let canceled = CompanionQuickActionPresentation(status: .canceled, companionName: "林嘉", isEnded: false)
        XCTAssertEqual(canceled.title, "重新邀请")
        XCTAssertEqual(canceled.accessibilityLabel, "同行，重新邀请林嘉")
        XCTAssertFalse(canceled.showsPendingIndicator)
        XCTAssertFalse(canceled.showsAvatars)
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
