import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class LiveActivityAndNotificationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    func testSystemsWithoutSchedulingWaitForTheActiveWindow() throws {
        let snapshot = makeSnapshot(timetableDays: [])
        let state = try XCTUnwrap(LiveActivityPlanner.desiredState(
            snapshot: snapshot, now: date(-24), coverFilename: nil
        )).state
        let existing = [LiveActivityExisting(showID: snapshot.showID.uuidString, isPending: false, state: state)]
        for activities in [[], existing] {
            let action = LiveActivityPlanner.action(
                snapshot: snapshot, now: date(-24), existing: activities,
                coverFilename: nil, supportsScheduling: false
            )
            switch action {
            case .none where activities.isEmpty, .endAll where !activities.isEmpty: break
            default: XCTFail("Old systems must not start or retain an activity before its window")
            }
        }
        let active = LiveActivityPlanner.action(
            snapshot: snapshot, now: date(10), existing: [],
            coverFilename: nil, supportsScheduling: false
        )
        guard case .request = active else { return XCTFail("Foreground start must remain available") }
    }

    // MARK: - 1. Live Activity Without Interested Shows (Objective Overview)

    func testLiveActivityStartsAndProvidesObjectiveOverviewWithoutInterested() {
        let p1 = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "The Strokes",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(14, 0),
            endsAt: date(15, 30),
            isInterested: false
        )
        let p2 = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "Yeah Yeah Yeahs",
            stageID: UUID(),
            stageName: "Sub Stage",
            startsAt: date(16, 0),
            endsAt: date(17, 30),
            isInterested: false
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [p1, p2])
        let snapshot = makeSnapshot(timetableDays: [day])

        // At 14:30 (during p1, p2 is next)
        let result = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(14, 30), coverFilename: nil)
        XCTAssertNotNil(result)
        let state = result!.state
        XCTAssertEqual(state.currentArtistName, "The Strokes")
        XCTAssertEqual(state.currentStageName, "Main Stage")
        XCTAssertEqual(state.nextArtistName, "Yeah Yeah Yeahs")
        XCTAssertFalse(state.isInterestedNext)
    }

    func testLiveActivityCarriesConcurrentArtistAndArtistImages() {
        let main = WidgetTimetablePerformance(
            id: UUID(), artistName: "Bonobo", stageID: UUID(), stageName: "Tent",
            startsAt: date(20, 0), endsAt: date(21, 0), isInterested: true, artistImageURL: "https://img/bonobo"
        )
        let other = WidgetTimetablePerformance(
            id: UUID(), artistName: "Coldplay", stageID: UUID(), stageName: "Main",
            startsAt: date(20, 0), endsAt: date(22, 0), isInterested: false, artistImageURL: "https://img/coldplay"
        )
        let later = WidgetTimetablePerformance(
            id: UUID(), artistName: "Pulp", stageID: UUID(), stageName: "Main",
            startsAt: date(22, 30), endsAt: date(23, 30), isInterested: false, artistImageURL: nil
        )
        let snapshot = makeSnapshot(timetableDays: [WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [main, other, later])])

        let state = LiveActivityPlanner.desiredState(
            snapshot: snapshot, now: date(20, 30), coverFilename: nil,
            artistImageFilename: { "la-" + $0 }
        )?.state

        XCTAssertEqual(state?.currentArtistName, "Bonobo")
        XCTAssertEqual(state?.alsoArtistName, "Coldplay")
        XCTAssertEqual(state?.alsoStageName, "Main")
        XCTAssertEqual(state?.currentArtistImageFilename, "la-https://img/bonobo")
        XCTAssertEqual(state?.alsoArtistImageFilename, "la-https://img/coldplay")
        XCTAssertNil(state?.nextArtistImageFilename)
        XCTAssertEqual(
            LiveActivityPlanner.featuredArtistImageSources(snapshot: snapshot, now: date(20, 30)),
            ["https://img/bonobo", "https://img/coldplay"]
        )
    }

    func testLiveActivityCountsDownToNextSetBetweenSets() {
        let p1 = WidgetTimetablePerformance(
            id: UUID(), artistName: "The Strokes", stageID: UUID(), stageName: "Main Stage",
            startsAt: date(14, 0), endsAt: date(15, 0), isInterested: false
        )
        let p2 = WidgetTimetablePerformance(
            id: UUID(), artistName: "Yeah Yeah Yeahs", stageID: UUID(), stageName: "Sub Stage",
            startsAt: date(16, 0), endsAt: date(17, 0), isInterested: false
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [p1, p2])

        let state = LiveActivityPlanner.desiredState(
            snapshot: makeSnapshot(timetableDays: [day]), now: date(15, 30), coverFilename: nil
        )?.state

        XCTAssertNil(state?.currentArtistName)
        XCTAssertEqual(state?.nextArtistName, "Yeah Yeah Yeahs")
        XCTAssertEqual(state?.startDate, date(16, 0))
    }

    // MARK: - 2. Live Activity With Interested Shows (Personal Next Priority)

    func testLiveActivityPrioritizesInterestedShowsWhenAvailable() {
        let pMain = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "Coldplay",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(20, 0),
            endsAt: date(22, 0),
            isInterested: false
        )
        let pTent = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "Bonobo",
            stageID: UUID(),
            stageName: "Electronic Tent",
            startsAt: date(20, 0),
            endsAt: date(21, 30),
            isInterested: true // User marked Bonobo as Want to See!
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [pMain, pTent])
        let snapshot = makeSnapshot(timetableDays: [day])

        // At 20:30 (both playing parallel, Bonobo is interested)
        let result = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(20, 30), coverFilename: nil)
        XCTAssertNotNil(result)
        let state = result!.state
        // Interested performance Bonobo must take precedence!
        XCTAssertEqual(state.currentArtistName, "Bonobo")
        XCTAssertEqual(state.currentStageName, "Electronic Tent")
    }

    func testLiveActivityCurrentArtistFollowsFocusedPerformance() throws {
        let focused = WidgetTimetablePerformance(
            id: UUID(), artistName: "Focused", stageID: UUID(), stageName: "Main Stage",
            startsAt: date(20, 15), endsAt: date(21, 0), isInterested: false
        )
        let interested = WidgetTimetablePerformance(
            id: UUID(), artistName: "Interested", stageID: UUID(), stageName: "Tent",
            startsAt: date(20, 0), endsAt: date(22, 0), isInterested: true
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [interested, focused])
        let snapshot = makeSnapshot(timetableDays: [day])
        let defaultState = try XCTUnwrap(LiveActivityPlanner.desiredState(
            snapshot: snapshot, now: date(20, 30), coverFilename: nil
        )?.state)
        let focusedState = try XCTUnwrap(LiveActivityPlanner.desiredState(
            snapshot: snapshot, now: date(20, 30), coverFilename: nil, focusedPerformanceID: focused.id
        )?.state)

        XCTAssertEqual(focusedState.currentArtistName, "Focused")
        XCTAssertEqual(focusedState.currentStageName, "Main Stage")
        XCTAssertEqual(focusedState.currentStartsAt, date(20, 15))
        XCTAssertEqual(LiveActivityPlanner.action(
            snapshot: snapshot, now: date(20, 30),
            existing: [LiveActivityExisting(showID: snapshot.showID.uuidString, isPending: false, state: defaultState)],
            coverFilename: nil, focusedPerformanceID: focused.id
        ), .update(focusedState))
    }

    // MARK: - 3. Multi-day Intermission: Ends Today, Restarts Next Day

    func testLiveActivityEndsAfterTodayAndRestartsNextDay() {
        // Day 1: 14:00 - 22:00
        let d1 = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "Blur",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(14, 0),
            endsAt: date(22, 0),
            isInterested: true
        )
        let day1 = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [d1])

        // Day 2: starts next day at 15:00 (+39 hours)
        let d2 = WidgetTimetablePerformance(
            id: UUID(),
            artistName: "Pulp",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(39, 0),
            endsAt: date(42, 0),
            isInterested: true
        )
        let day2 = WidgetTimetableDay(id: UUID(), date: date(24, 0), performances: [d2])
        let snapshot = makeSnapshot(timetableDays: [day1, day2])

        // At 23:00 (after Day 1 ends, before Day 2 starts)
        let intermissionResult = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(23, 0), coverFilename: nil)
        XCTAssertNil(intermissionResult, "Activity must automatically end once today's sets are completed")

        // At 38:00 (1 hour before Day 2 starts, inside active window)
        let day2Result = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(38, 0), coverFilename: nil)
        XCTAssertNotNil(day2Result, "Activity must be restartable for the next festival day")
        XCTAssertEqual(day2Result?.state.nextArtistName, "Pulp")
    }

    // MARK: - 4. Personal Notifications: ONLY For Interested Sets

    func testPersonalNotificationsOnlyScheduledForInterestedPerformances() throws {
        let showDate = date(10, 0)
        let show = try Show(
            name: "Summer Sonic 2026",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Taipei"
        )
        context.insert(show)

        // 3 sets: p1 (not interested), p2 (interested), p3 (interested)
        let p1 = try TimetablePerformance(artistName: "Band A", startsAt: date(14, 0), endsAt: date(15, 0))
        p1.isInterested = false
        let p2 = try TimetablePerformance(artistName: "Band B", startsAt: date(16, 0), endsAt: date(17, 0))
        p2.isInterested = true
        let p3 = try TimetablePerformance(artistName: "Band C", startsAt: date(19, 0), endsAt: date(20, 0))
        p3.isInterested = true

        let stage = try TimetableStage(name: "Mountain Stage", performances: [p1, p2, p3])
        let day = try TimetableDay(date: date(0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day])
        timetable.show = show
        show.timetable = timetable
        context.insert(timetable)
        try context.save()

        let scheduler = LocalNotificationScheduler(calendar: Calendar(identifier: .gregorian))
        let requests = scheduler.futureRequests(for: show, now: date(10, 0))

        let interestedNotifications = requests.filter { $0.milestone == .interestedPerformance }
        // Exactly 2 notifications for Band B and Band C, NONE for Band A!
        XCTAssertEqual(interestedNotifications.count, 2)

        let targetNames = interestedNotifications.map(\.title)
        XCTAssertTrue(targetNames.contains(where: { $0.contains("Band B") }))
        XCTAssertTrue(targetNames.contains(where: { $0.contains("Band C") }))
        XCTAssertFalse(targetNames.contains(where: { $0.contains("Band A") }))

        // Fixed 15 minutes lead time verification
        let p2Notification = interestedNotifications.first { $0.performanceID == p2.id }!
        XCTAssertEqual(p2Notification.fireDate, date(16, 0).addingTimeInterval(-15 * 60))

        // Untoggling interest removes the notification on next schedule
        p2.isInterested = false
        try context.save()

        let updatedRequests = scheduler.futureRequests(for: show, now: date(10, 0))
        let updatedInterested = updatedRequests.filter { $0.milestone == .interestedPerformance }
        XCTAssertEqual(updatedInterested.count, 1)
        XCTAssertEqual(updatedInterested.first?.performanceID, p3.id)
    }

    // MARK: - Boundary Refresh

    func testLiveActivityAdvancesToNextArtistAtSetBoundaries() throws {
        let (snapshot, _, _) = makeTwoSetFestival()

        let between = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(15, 31), coverFilename: nil)).state
        XCTAssertNil(between.currentArtistName)
        XCTAssertEqual(between.nextArtistName, "Yeah Yeah Yeahs")

        let second = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(16, 0), coverFilename: nil)).state
        XCTAssertEqual(second.currentArtistName, "Yeah Yeah Yeahs")
    }

    func testNextRefreshDateLandsOnEachTimetableBoundary() {
        let (snapshot, _, _) = makeTwoSetFestival()

        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(14, 30)), date(15, 30))
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(15, 30)), date(16, 0))
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(16, 30)), date(17, 30))
        XCTAssertNil(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(17, 30)))
    }

    func testNextRefreshDateIncludesStartingSoonThreshold() {
        let (snapshot, _, _) = makeTwoSetFestival(secondStartsAt: date(17, 0), secondEndsAt: date(18, 0))

        // 下一场开演前 30 分钟,「即将开始」标记会翻转。
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(15, 31)), date(16, 30))
    }

    func testNextRefreshDateFlipsStandardShowAtStart() {
        let snapshot = makeSnapshot(timetableDays: [])

        // 启动窗口起点为 10:00 - 30m = 09:30
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(9, 0)), date(9, 30))
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(9, 30)), date(10, 0))
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(10, 0)), date(14, 0))
        XCTAssertNil(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(14, 0)))
        XCTAssertNil(LiveActivityPlanner.nextRefreshDate(snapshot: nil, now: date(9, 0)))
    }

    // MARK: - Issue #359: 启动窗口、内容过期与散场收起

    func testEarliestStartRespectsThirtyMinutesLeadAndEightHoursCap() {
        // 1. 20:00 - 22:00 普通现场 (2h): 开场前 30m = 19:30, 谢幕前 8h = 14:00 -> 较晚者为 19:30
        let start20 = date(20, 0)
        let end22 = date(22, 0)
        XCTAssertEqual(
            LiveActivityPlanner.earliestStart(activityStart: start20, activityEnd: end22),
            date(19, 30)
        )

        // 2. 12:00 - 23:00 音乐节单日 (11h): 开场前 30m = 11:30, 谢幕前 8h = 15:00 -> 较晚者为 15:00
        let start12 = date(12, 0)
        let end23 = date(23, 0)
        XCTAssertEqual(
            LiveActivityPlanner.earliestStart(activityStart: start12, activityEnd: end23),
            date(15, 0)
        )

        // 3. 音乐节换场或切换聚焦不改变当日启动窗口
        let p1 = WidgetTimetablePerformance(
            id: UUID(), artistName: "Band 1", stageID: UUID(), stageName: "Main",
            startsAt: date(14, 0), endsAt: date(15, 0), isInterested: false
        )
        let p2 = WidgetTimetablePerformance(
            id: UUID(), artistName: "Band 2", stageID: UUID(), stageName: "Main",
            startsAt: date(16, 0), endsAt: date(17, 0), isInterested: false
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [p1, p2])
        let festivalSnapshot = makeSnapshot(timetableDays: [day])

        let desiredEarly = LiveActivityPlanner.desiredState(snapshot: festivalSnapshot, now: date(13, 0), coverFilename: nil)!
        let desiredLater = LiveActivityPlanner.desiredState(snapshot: festivalSnapshot, now: date(15, 30), coverFilename: nil)!
        let earliestEarly = LiveActivityPlanner.earliestStart(activityStart: desiredEarly.dayStart, activityEnd: desiredEarly.activityEnd)
        let earliestLater = LiveActivityPlanner.earliestStart(activityStart: desiredLater.dayStart, activityEnd: desiredLater.activityEnd)
        XCTAssertEqual(earliestEarly, earliestLater, "换场不应改变当日活动启动窗口")
        XCTAssertEqual(earliestEarly, date(13, 30), "14:00 首演的音乐节应在 13:30 启动")
    }

    func testNextRefreshDateIncludesEarliestStartAndEndBoundaries() {
        let (snapshot, _, _) = makeTwoSetFestival()
        // 当日首场 14:00，启动窗口 13:30
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(12, 0)), date(13, 30))
        // 终场结束 17:30
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: date(17, 0)), date(17, 30))
    }

    func testDegradationWhenPerformanceEndsWithoutUpdate() {
        let (snapshot, p1, p2) = makeTwoSetFestival()
        let stateDuringP1 = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(14, 30), coverFilename: nil)!.state
        XCTAssertEqual(stateDuringP1.currentArtistName, p1.artistName)

        // P1 已于 15:30 结束。若 App 挂起未更新，在 15:35 渲染时：
        let contentAtBreak = LiveActivityContent(state: stateDuringP1, isStale: true, now: date(15, 35))
        XCTAssertNotEqual(contentAtBreak.mode, .set, "已结束的艺人不能继续显示正在演出")
        XCTAssertEqual(contentAtBreak.mode, .between, "应降级为场间倒数下一场")
        XCTAssertEqual(contentAtBreak.title, p2.artistName)

        // 下一场预定 16:00 开演。若到 16:15 依然未收到更新（下一场未知）：
        let contentAfterNextStart = LiveActivityContent(state: stateDuringP1, isStale: true, now: date(16, 15))
        XCTAssertNotEqual(contentAfterNextStart.mode, .set)
        XCTAssertEqual(contentAfterNextStart.title, snapshot.name, "缺乏确定状态时应回到现场身份")
    }

    func testIsStaleDoesNotDirectlyEqualEnded() {
        let snapshot = makeSnapshot(timetableDays: [])
        let state = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(11, 0), coverFilename: nil)!.state
        // 演出中途网络滞后导致的 isStale = true，不能直接变成已散场
        let content = LiveActivityContent(state: state, isStale: true, now: date(11, 0))
        XCTAssertNotEqual(content.mode, .ended, "isStale 不等于已散场")
        XCTAssertEqual(content.mode, .started)
    }

    func testNaturalEndDismissesAfterFifteenMinutes() {
        let snapshot = makeSnapshot(timetableDays: [])
        // 演出 10:00 - 14:00，14:00 结束
        let desiredAtEnd = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(14, 5), coverFilename: nil)
        XCTAssertNil(desiredAtEnd, "演出结束后 desiredState 为 nil")

        let existingState = LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(13, 0), coverFilename: nil)!.state
        let existing = [LiveActivityExisting(showID: snapshot.showID.uuidString, isPending: false, state: existingState)]

        // 14:05: 刚过结束点 5 分钟，仍在 15 分钟展示窗口内 -> 自然结束，带有 15 分钟 dismissal
        let actionWithin15m = LiveActivityPlanner.action(
            snapshot: snapshot, now: date(14, 5), existing: existing, coverFilename: nil
        )
        guard case .endNaturally(let finalState, let dismissDate) = actionWithin15m else {
            return XCTFail("自然结束点应返回 .endNaturally")
        }
        XCTAssertTrue(finalState.isEnded ?? false, "最终态应标记为已结束")
        XCTAssertEqual(dismissDate, date(14, 15), "应在散场 15 分钟后收起")

        // 14:20: 超过散场 15 分钟 -> 立即清除
        let actionAfter15m = LiveActivityPlanner.action(
            snapshot: snapshot, now: date(14, 20), existing: existing, coverFilename: nil
        )
        XCTAssertEqual(actionAfter15m, .endAll)

        // 异常结束（如取消现场）-> 无论何时都应立即清除，不保留 15 分钟
        var canceledSnapshot = snapshot
        canceledSnapshot.timing.changeStatus = .canceled
        let actionCanceled = LiveActivityPlanner.action(
            snapshot: canceledSnapshot, now: date(14, 5), existing: existing, coverFilename: nil
        )
        XCTAssertEqual(actionCanceled, .endAll)
    }

    func testContentStateBackwardsCompatibilityDecoding() throws {
        // 仅包含旧版本字段的 JSON
        let oldJson = """
        {
            "showName": "Summer Festival",
            "startDate": 1790956800,
            "hasStarted": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(ShowLiveActivityAttributes.ContentState.self, from: oldJson)
        XCTAssertEqual(state.showName, "Summer Festival")
        XCTAssertEqual(state.isEnded, false)
        XCTAssertNil(state.contentExpirationDate)
    }

    // MARK: - Issue #360 Tests: 15-minute Want-to-See Reminder & Transition Plan

    func testWantToSeeReminderActivatesAtFifteenMinutesLead() throws {
        // Main set at 14:00-15:30 (not interested)
        // Set 2 at 16:00-17:30 with isInterested = true
        let (snapshot, _, second) = makeTwoSetFestival()
        var days = snapshot.timetable!.days
        let perf2 = WidgetTimetablePerformance(
            id: second.id,
            artistName: "Bonobo",
            stageID: second.stageID,
            stageName: "Green Stage",
            startsAt: second.startsAt,
            endsAt: second.endsAt,
            isInterested: true
        )
        days[0] = WidgetTimetableDay(id: days[0].id, date: days[0].date, performances: [days[0].performances[0], perf2])
        let festival = makeSnapshot(timetableDays: days)

        // At 15:20 (40 mins before 16:00): not in reminder window, not in startingSoon window
        let state40 = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: festival, now: date(15, 20), coverFilename: nil)).state
        XCTAssertFalse(state40.isReminderActive)
        XCTAssertNil(state40.reminderArtistName)

        // At 15:35 (25 mins before 16:00): in 30m startingSoon window, but NOT 15m reminder window!
        let state25 = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: festival, now: date(15, 35), coverFilename: nil)).state
        XCTAssertFalse(state25.isReminderActive, "30-min visual threshold must not activate reminder")
        XCTAssertNil(state25.reminderArtistName)

        // At 15:45 (15 mins before 16:00): exactly in 15m reminder window!
        let state15 = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: festival, now: date(15, 45), coverFilename: nil)).state
        XCTAssertTrue(state15.isReminderActive)
        XCTAssertEqual(state15.reminderArtistName, "Bonobo")
        XCTAssertEqual(state15.reminderStageName, "Green Stage")
        XCTAssertEqual(state15.reminderStartsAt, date(16, 0))

        // Content presentation in LiveActivityContent:
        let content15 = LiveActivityContent(state: state15, isStale: false, now: date(15, 45))
        XCTAssertEqual(content15.mode, .reminder)
        XCTAssertEqual(content15.kicker, "快开始了")
        XCTAssertEqual(content15.title, "Bonobo")
        XCTAssertTrue(content15.subtitle?.contains("Green Stage") == true)

        // At 16:00: show starts! Reminder expires and silently switches to .set (Now Playing)
        let stateStart = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: festival, now: date(16, 0), coverFilename: nil)).state
        XCTAssertFalse(stateStart.isReminderActive, "Reminder must expire once performance starts")
        let contentStart = LiveActivityContent(state: stateStart, isStale: false, now: date(16, 0))
        XCTAssertEqual(contentStart.mode, .set)
        XCTAssertEqual(contentStart.kicker, "正在演出")
        XCTAssertEqual(contentStart.title, "Bonobo")
    }

    func testMultipleInterestedPerformancesSummary() throws {
        // Two performances starting at 16:00 simultaneously on different stages
        let p1 = WidgetTimetablePerformance(
            id: UUID(), artistName: "Band 1", stageID: UUID(), stageName: "Stage 1",
            startsAt: date(16, 0), endsAt: date(17, 0), isInterested: true
        )
        let p2 = WidgetTimetablePerformance(
            id: UUID(), artistName: "Band 2", stageID: UUID(), stageName: "Stage 2",
            startsAt: date(16, 0), endsAt: date(17, 0), isInterested: true
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [p1, p2])
        let snapshot = makeSnapshot(timetableDays: [day])

        let state = try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(15, 45), coverFilename: nil)).state
        XCTAssertTrue(state.isReminderActive)
        XCTAssertEqual(state.reminderPerformanceIDs?.count, 2)
        XCTAssertNotNil(state.reminderSummary)
        XCTAssertTrue(state.reminderSummary?.contains("Band 1") == true)
        XCTAssertTrue(state.reminderSummary?.contains("Band 2") == true)
    }

    func testNextRefreshDateIncludesFifteenMinuteReminderBoundary() throws {
        let (snapshot, _, second) = makeTwoSetFestival()
        var days = snapshot.timetable!.days
        let perf2 = WidgetTimetablePerformance(
            id: second.id,
            artistName: "Bonobo",
            stageID: second.stageID,
            stageName: "Green Stage",
            startsAt: date(16, 0),
            endsAt: date(17, 0),
            isInterested: true
        )
        days[0] = WidgetTimetableDay(id: days[0].id, date: days[0].date, performances: [days[0].performances[0], perf2])
        let festival = makeSnapshot(timetableDays: days)

        // At 15:40: next refresh boundary must be 15:45 (T-15m reminder fire time)!
        let next = LiveActivityPlanner.nextRefreshDate(snapshot: festival, now: date(15, 40))
        XCTAssertEqual(next, date(15, 45))
    }

    func testTransitionPlanGenerationUnder4KB() throws {
        let (snapshot, _, second) = makeTwoSetFestival()
        var days = snapshot.timetable!.days
        let perf2 = WidgetTimetablePerformance(
            id: second.id,
            artistName: "Bonobo",
            stageID: second.stageID,
            stageName: "Green Stage",
            startsAt: date(16, 0),
            endsAt: date(17, 30),
            isInterested: true
        )
        days[0] = WidgetTimetableDay(id: days[0].id, date: days[0].date, performances: [days[0].performances[0], perf2])
        let festival = makeSnapshot(timetableDays: days)

        let plan = try XCTUnwrap(LiveActivityTransitionPlanBuilder.buildPlan(
            snapshot: festival,
            now: date(14, 0),
            appInstanceID: "test-device-uuid",
            activityPushToken: "test-apns-token-hex",
            isProduction: false,
            version: 1
        ))

        XCTAssertEqual(plan.version, 1)
        XCTAssertFalse(plan.steps.isEmpty)
        XCTAssertEqual(plan.showID, festival.showID.uuidString)

        // Verify each payload step is under 4 KB (platform budget limit)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        for step in plan.steps {
            let stepData = try encoder.encode(step.state)
            XCTAssertLessThan(stepData.count, 4096, "Step state exceeds 4KB APNs limit")
        }
    }

    // MARK: - Issue #362 Tests: Handover & Arbitration

    func testHandoverDefaultToLocalAndCompletesWhenEligible() async throws {
        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: UUID().uuidString,
            performanceID: UUID().uuidString,
            scheduledStartsAt: date(16, 0)
        )

        // 1. Default channel is localNotification
        let initial = await ledger.record(for: eventKey)
        XCTAssertEqual(initial.channel, .localNotification)
        XCTAssertEqual(initial.status, .pending)

        // 2. Handover before reminder trigger (at 15:30, trigger is 15:45)
        let handoverSuccess = await ledger.completeHandover(
            eventKey: eventKey,
            planVersion: 1,
            now: date(15, 30)
        )
        XCTAssertTrue(handoverSuccess)

        let handedOver = await ledger.record(for: eventKey)
        XCTAssertEqual(handedOver.channel, .liveActivity)
        XCTAssertEqual(handedOver.status, .handedOver)
        XCTAssertEqual(handedOver.planVersion, 1)

        // 3. Handover after trigger point fails (e.g. at 15:50)
        let lateKey = PerformanceReminderEventKey(
            showID: UUID().uuidString,
            performanceID: UUID().uuidString,
            scheduledStartsAt: date(16, 0)
        )
        let lateHandover = await ledger.completeHandover(
            eventKey: lateKey,
            planVersion: 1,
            now: date(15, 50)
        )
        XCTAssertFalse(lateHandover, "Late handover must be rejected")
    }

    func testConcurrentConsumptionOnlySucceedsOnce() async throws {
        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: UUID().uuidString,
            performanceID: UUID().uuidString,
            scheduledStartsAt: date(16, 0)
        )

        _ = await ledger.completeHandover(eventKey: eventKey, planVersion: 1, now: date(15, 0))

        // Trigger time is 15:45. Test consumption at 15:46
        let now = date(15, 46)

        // Simulate concurrent attempts (e.g. app foreground vs background remote task)
        async let consume1 = ledger.tryConsume(eventKey: eventKey, by: .liveActivity, now: now)
        async let consume2 = ledger.tryConsume(eventKey: eventKey, by: .liveActivity, now: now)
        async let wrongChannel = ledger.tryConsume(eventKey: eventKey, by: .localNotification, now: now)

        let (res1, res2, resWrong) = await (consume1, consume2, wrongChannel)

        // Exactly one liveActivity consumption succeeds, wrong channel rejected
        XCTAssertTrue(res1 != res2, "Exactly one concurrent consume must succeed")
        XCTAssertFalse(resWrong, "Wrong channel cannot consume handed-over event")

        // Subsequent consume attempt fails
        let subsequent = await ledger.tryConsume(eventKey: eventKey, by: .liveActivity, now: now)
        XCTAssertFalse(subsequent)
    }

    func testRevocationToLocalBeforeTriggerPoint() async throws {
        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: UUID().uuidString,
            performanceID: UUID().uuidString,
            scheduledStartsAt: date(16, 0)
        )

        _ = await ledger.completeHandover(eventKey: eventKey, planVersion: 1, now: date(15, 0))

        // Revoke at 15:30 (before trigger at 15:45)
        let revokeSuccess = await ledger.revokeToLocal(eventKey: eventKey, now: date(15, 30))
        XCTAssertTrue(revokeSuccess)

        let record = await ledger.record(for: eventKey)
        XCTAssertEqual(record.channel, .localNotification)
        XCTAssertEqual(record.status, .pending)

        // Revoke after trigger point (15:50) fails
        _ = await ledger.completeHandover(eventKey: eventKey, planVersion: 2, now: date(15, 35))
        let lateRevoke = await ledger.revokeToLocal(eventKey: eventKey, now: date(15, 50))
        XCTAssertFalse(lateRevoke, "Cannot revoke after reminder trigger passed")
    }

    // MARK: - Helpers

    private func makeTwoSetFestival(
        secondStartsAt: Date? = nil,
        secondEndsAt: Date? = nil
    ) -> (WidgetShowSnapshot, WidgetTimetablePerformance, WidgetTimetablePerformance) {
        let first = WidgetTimetablePerformance(
            id: UUID(), artistName: "The Strokes", stageID: UUID(), stageName: "Main Stage",
            startsAt: date(14, 0), endsAt: date(15, 30), isInterested: false
        )
        let second = WidgetTimetablePerformance(
            id: UUID(), artistName: "Yeah Yeah Yeahs", stageID: UUID(), stageName: "Sub Stage",
            startsAt: secondStartsAt ?? date(16, 0), endsAt: secondEndsAt ?? date(17, 30), isInterested: false
        )
        let day = WidgetTimetableDay(id: UUID(), date: date(0, 0), performances: [first, second])
        return (makeSnapshot(timetableDays: [day]), first, second)
    }

    private func makeSnapshot(timetableDays: [WidgetTimetableDay]) -> WidgetShowSnapshot {
        WidgetShowSnapshot(
            showID: UUID(),
            name: "Fuji Rock 2026",
            city: "Naeba",
            venueName: "Naeba Ski Resort",
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: date(0, 0),
                startTime: date(10, 0),
                endDate: nil,
                endTime: nil,
                timeZoneSecondsFromGMT: 8 * 3600,
                endTimeZoneSecondsFromGMT: nil,
                timeZoneIdentifier: "Asia/Taipei",
                endTimeZoneIdentifier: nil,
                endedAt: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date(),
            timetable: WidgetTimetableSnapshot(days: timetableDays)
        )
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1790956800 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
