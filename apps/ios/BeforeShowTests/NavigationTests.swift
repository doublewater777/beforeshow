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

    func testAddShowEntryCopyStatesSupportedLinkPlatformsAndPrivacyBoundary() {
        XCTAssertEqual(
            AddShowMethodCopy.screenshot.subtitle,
            "选择票务截图，仅在本机识别，图片不会上传。"
        )
        XCTAssertEqual(
            AddShowMethodCopy.link.subtitle,
            "粘贴支持平台的票务链接，需要联网解析。"
        )
    }

    func testEditedShowDraftRequiresExplicitDiscardConfirmation() {
        let initial = ShowDraft(name: "现场")
        var edited = initial
        edited.venueName = "新场馆"

        XCTAssertFalse(
            ShowDraftEditorExitPolicy.requiresDiscardConfirmation(
                current: initial,
                initial: initial
            )
        )
        XCTAssertTrue(
            ShowDraftEditorExitPolicy.requiresDiscardConfirmation(
                current: edited,
                initial: initial
            )
        )
    }

    func testShowDetailInformationKeepsAddressDetails() {
        XCTAssertEqual(
            ShowDetailInformationPolicy.venueDetail(address: "信义路 1 号", city: "台北"),
            "信义路 1 号 · 台北"
        )
    }

    func testShowDetailExperienceOffersCompanionAndMemoryEntries() {
        XCTAssertEqual(
            ShowDetailExperienceAction.allCases.map(\.rawValue),
            ["同行", "记忆碎片"]
        )
    }

    /// 设置不是主导航项；当前现场主海报也不承载溢出菜单。
    func testSettingsIsNotAMainTab() {
        XCTAssertFalse(BeforeShowTab.allCases.contains { $0.rawValue == "设置" })
    }

    func testPassiveHomeReturnDoesNotPresentBackgroundCompanionError() {
        XCTAssertNil(
            CompanionHomeMessagePolicy.message(
                accepted: nil,
                backgroundError: "需要登录 iCloud 才能邀请同行"
            )
        )
        XCTAssertEqual(
            CompanionHomeMessagePolicy.message(
                accepted: "已与朋友确认同行",
                backgroundError: "需要登录 iCloud 才能邀请同行"
            ),
            "已与朋友确认同行"
        )
    }

    func testMyShowsOverflowMenuMatchesShowStatus() {
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .scheduled,
                timeKind: .before,
                canSetCurrent: true
            ),
            [.view, .setCurrent, .edit, .postpone, .cancel, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .scheduled,
                timeKind: .today,
                canSetCurrent: false
            ),
            [.view, .edit, .postpone, .cancel, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .postponed,
                timeKind: .postponed,
                canSetCurrent: false
            ),
            [.view, .editPostponedDate, .restoreScheduled, .cancel, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .postponed,
                timeKind: .before,
                canSetCurrent: true
            ),
            [.view, .setCurrent, .editPostponedDate, .restoreScheduled, .cancel, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .canceled,
                timeKind: .canceled,
                canSetCurrent: false
            ),
            [.view, .restoreCanceled, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .scheduled,
                timeKind: .ended,
                canSetCurrent: false
            ),
            [.view, .edit, .delete]
        )
        XCTAssertEqual(
            CurrentShowLibraryMenuPolicy.actions(
                for: .scheduled,
                timeKind: .postShow,
                canSetCurrent: true
            ),
            [.view, .setCurrent, .edit, .delete]
        )
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
            CurrentShowQuickAction.actions(for: .pre),
            [.route, .ticket, .timetable, .companion, .memoryFragments]
        )
        XCTAssertEqual(
            CurrentShowQuickAction.actions(for: .ended),
            [.memoryFragments, .companion, .route, .ticket, .timetable]
        )
    }

    func testMemoryCreateSourceUsesDialogCopy() {
        XCTAssertEqual(MemoryCreateSourcePresentation.title, "新增记忆")
        XCTAssertEqual(
            MemoryCreateSourceOption.allCases.map(\.rawValue),
            ["相机", "图库", "文字"]
        )
        XCTAssertEqual(
            MemoryCreateSourceOption.allCases.map(\.iconName),
            ["camera", "photo.on.rectangle", "text.alignleft"]
        )
        XCTAssertEqual(
            MemoryCreateSourceOption.allCases.map(\.subtitle),
            ["打开系统相机", "照片或视频", "写一句话"]
        )
    }

    func testAssetsAndMemoryOpenAsSheets() {
        XCTAssertEqual(ShowAssetPresentationStyle.style(hasSavedAsset: false), .sheet)
        XCTAssertEqual(ShowAssetPresentationStyle.style(hasSavedAsset: true), .sheet)
        XCTAssertEqual(CurrentShowPresentedSheet.memory.id, "memory")
        XCTAssertEqual(ShowDetailPresentedSheet.memory.id, "memory")
    }

    func testAssetSheetUsesDetailVisibilityHandoff() {
        XCTAssertTrue(
            DetailVisibilityHandoff.tabBarHidden(after: .assetSheetPresented)
        )
        XCTAssertFalse(
            DetailVisibilityHandoff.tabBarHidden(after: .assetSheetDismissed)
        )
    }

    func testHomeAndDetailSheetsReplaceInsteadOfStacking() {
        var home: CurrentShowPresentedSheet? = .companion
        home = .endConfirmation
        XCTAssertEqual(home, .endConfirmation)

        var detail: ShowDetailPresentedSheet? = .editor
        detail = .postpone
        XCTAssertEqual(detail, .postpone)

        var paywall: AddShowPaywallSheet? = .limit
        paywall = .membership
        XCTAssertEqual(paywall, .membership)
    }

    func testMapChooserDialogHidesAppsWithoutADestination() {
        let installed: [ExternalMapApp] = [.apple, .amap]
        XCTAssertTrue(
            MapChooserPresentation.visibleApps(hasDestination: false, installed: installed).isEmpty
        )
        XCTAssertEqual(
            MapChooserPresentation.visibleApps(hasDestination: true, installed: installed),
            installed
        )
        XCTAssertEqual(
            MapChooserPresentation.message(
                hasDestination: false,
                destinationLabel: "南京奥体中心体育场",
                installed: installed
            ),
            "补充场馆或地址后，就能跳到地图 App。"
        )
        XCTAssertEqual(
            MapChooserPresentation.message(
                hasDestination: true,
                destinationLabel: "南京奥体中心体育场",
                installed: installed
            ),
            "南京奥体中心体育场"
        )
        XCTAssertEqual(
            MapChooserPresentation.message(
                hasDestination: true,
                destinationLabel: "南京奥体中心体育场",
                installed: []
            ),
            "没有检测到可用的地图 App。"
        )
        XCTAssertEqual(
            MapChooserPresentation.resolution(hasDestination: true, installed: [.apple]),
            .pick([.apple])
        )
        XCTAssertEqual(
            MapChooserPresentation.resolution(hasDestination: true, installed: installed),
            .pick(installed)
        )
        XCTAssertEqual(
            MapChooserPresentation.resolution(hasDestination: false, installed: installed),
            .missingDestination
        )
        XCTAssertEqual(
            MapChooserPresentation.resolution(hasDestination: true, installed: []),
            .noneInstalled
        )
    }

    func testLibraryMenuMarksCancelAndDeleteDestructive() {
        XCTAssertTrue(CurrentShowLibraryMenuAction.delete.isDestructive)
        XCTAssertTrue(CurrentShowLibraryMenuAction.cancel.isDestructive)
        XCTAssertFalse(CurrentShowLibraryMenuAction.edit.isDestructive)
        XCTAssertFalse(CurrentShowLibraryMenuAction.view.isDestructive)
    }

    func testAddShowSheetCanDriveNavigationStack() {
        let sheets: [AddShowSheet] = [.manual, .screenshot, .link]
        XCTAssertEqual(Set(sheets.map(\.id)).count, 3)
        XCTAssertEqual(AddShowSheet.manual, AddShowSheet.manual)
    }

    func testDangerConfirmationsKeepTheExistingCopy() {
        XCTAssertEqual(DangerConfirmation.deleteShow.title, "删除这条现场记录？")
        XCTAssertEqual(DangerConfirmation.deleteShow.confirmTitle, "确认删除")
        XCTAssertEqual(DangerConfirmation.cancelShow.title, "取消这场演出？")
        XCTAssertEqual(DangerConfirmation.clearLocalData.confirmTitle, "清除")
        XCTAssertEqual(DangerConfirmation.deleteAsset(.ticket).title, "删除票根？")
        XCTAssertEqual(DangerConfirmation.deleteMemory.title, "删除这条记忆？")
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

    func testEstimatedEndAsksToEndUntilRealEndIsConfirmed() throws {
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
                hasConfirmedEnd: false,
                hasEndHandler: true
            ),
            "确认已结束"
        )
        XCTAssertNil(
            HomeCountdownLockup.endActionTitle(
                phase: phase,
                timeState: timeState,
                hasConfirmedEnd: true,
                hasEndHandler: true
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

    func testLiveEndActionIsHiddenWhenItsHandlerIsUnavailable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 7, day: 8, hour: 19, minute: 0, calendar: calendar)
        let endDate = makeDate(year: 2026, month: 7, day: 10, hour: 0, minute: 0, calendar: calendar)
        let dailyEnd = makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 0, calendar: calendar)
        let show = try Show(name: "三日音乐节", date: start, startTime: start, endDate: endDate, endTime: dailyEnd)
        let middleDay = makeDate(year: 2026, month: 7, day: 9, hour: 20, minute: 0, calendar: calendar)
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: middleDay)
        let phase = HomeShowPhase(timeState: state, now: middleDay)

        XCTAssertEqual(phase, .live)
        XCTAssertNil(
            HomeCountdownLockup.primaryAction(
                phase: phase,
                timeState: state,
                hasConfirmedEnd: false,
                hasEndHandler: false
            )
        )
    }

    func testPostShowEndConfirmationBackDismissesInsteadOfReturningToChoice() {
        var didShowChoice = false
        var didDismiss = false

        CurrentShowEndConfirmationSheet.performEarlierBackAction(
            allowsJustEnded: false,
            showChoice: { didShowChoice = true },
            dismiss: { didDismiss = true }
        )
        XCTAssertFalse(didShowChoice)
        XCTAssertTrue(didDismiss)

        didShowChoice = false
        didDismiss = false
        CurrentShowEndConfirmationSheet.performEarlierBackAction(
            allowsJustEnded: true,
            showChoice: { didShowChoice = true },
            dismiss: { didDismiss = true }
        )
        XCTAssertTrue(didShowChoice)
        XCTAssertFalse(didDismiss)
    }

    func testConfirmedEndPolicyAllowsHistoricalTimeOnlyWithinShowBounds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 8, day: 8, hour: 19, minute: 0, calendar: calendar)
        let show = try Show(name: "散场时间现场", date: start, startTime: start)
        let now = makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 0, calendar: calendar)

        XCTAssertTrue(CurrentShowEndPolicy.isValidConfirmedEnd(
            makeDate(year: 2026, month: 8, day: 8, hour: 22, minute: 0, calendar: calendar),
            for: show,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(CurrentShowEndPolicy.isValidConfirmedEnd(start.addingTimeInterval(-60), for: show, now: now, calendar: calendar))
        XCTAssertFalse(CurrentShowEndPolicy.isValidConfirmedEnd(now.addingTimeInterval(60), for: show, now: now, calendar: calendar))
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

    func testHomeIdentityStatusUsesCurrentLifecycleCopy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 8, day: 8, hour: 19, minute: 0, calendar: calendar)
        let show = try Show(name: "状态现场", date: start, startTime: start)

        let before = CurrentShowTimeState(show: show, calendar: calendar, now: start.addingTimeInterval(-3_600))
        XCTAssertEqual(HomeShowIdentityPresentation.statusText(for: before, now: start.addingTimeInterval(-3_600)), "今天开场")

        let live = CurrentShowTimeState(show: show, calendar: calendar, now: start.addingTimeInterval(60))
        XCTAssertEqual(HomeShowIdentityPresentation.statusText(for: live, now: start.addingTimeInterval(60)), "正在现场")

        show.markCanceled()
        let canceled = CurrentShowTimeState(show: show, calendar: calendar, now: start)
        XCTAssertEqual(HomeShowIdentityPresentation.statusText(for: canceled, now: start), "已取消")
    }

    func testHomeIdentityVenueSummaryAvoidsDuplicateCity() {
        XCTAssertEqual(
            HomeShowIdentityPresentation.venueSummary(venue: "上海梅赛德斯-奔驰文化中心", city: "上海"),
            "上海梅赛德斯-奔驰文化中心"
        )
        XCTAssertEqual(
            HomeShowIdentityPresentation.venueSummary(venue: "梅赛德斯-奔驰文化中心", city: "上海"),
            "梅赛德斯-奔驰文化中心 · 上海"
        )
        XCTAssertEqual(HomeShowIdentityPresentation.venueSummary(venue: nil, city: "上海"), "上海")
        XCTAssertNil(HomeShowIdentityPresentation.venueSummary(venue: "  ", city: " "))
    }

    func testHomeIdentityDateTextKeepsSingleDayTimeAndDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 8, day: 8, hour: 19, minute: 0, calendar: calendar)
        let end = makeDate(year: 2026, month: 8, day: 8, hour: 21, minute: 30, calendar: calendar)
        let show = try Show(name: "日期现场", date: start, startTime: start, endTime: end)
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: start.addingTimeInterval(-86_400))

        XCTAssertEqual(
            HomeShowIdentityPresentation.dateText(for: show, timeState: state, calendar: calendar),
            "2026.08.08 周六 19:00 · 预计演出 2 小时 30 分"
        )
    }

    func testHomeIdentityDateTextKeepsEndYearAcrossNewYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(year: 2026, month: 12, day: 31, hour: 19, minute: 0, calendar: calendar)
        let end = makeDate(year: 2027, month: 1, day: 1, hour: 21, minute: 0, calendar: calendar)
        let show = try Show(name: "跨年现场", date: start, startTime: start, endDate: end, endTime: end)
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: start.addingTimeInterval(-86_400))

        XCTAssertEqual(
            HomeShowIdentityPresentation.dateText(for: show, timeState: state, calendar: calendar),
            "2026.12.31-2027.01.01 · 每日 19:00-21:00"
        )
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
