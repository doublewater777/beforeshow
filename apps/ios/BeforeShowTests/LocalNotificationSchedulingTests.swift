import SwiftData
import XCTest
@testable import BeforeShow

final class LocalNotificationSchedulingTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 10)
    }

    func testPermissionIsRequestedOnlyAfterUserHasAddedShow() {
        let policy = NotificationPermissionPolicy()

        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: false,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertTrue(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .authorized,
            hasRequestedPermissionAfterFirstShow: false
        ))
        XCTAssertFalse(policy.shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: true
        ))
    }

    func testPermissionRequestWaitsForVisibleCurrentShowWithFutureReminderValue() {
        let policy = NotificationPermissionPolicy()

        for kind in [CurrentShowTimeKind.before, .today, .dayEnded] {
            XCTAssertTrue(policy.shouldRequestOnCurrentShow(
                authorizationState: .notDetermined,
                hasRequestedPermissionAfterFirstShow: false,
                currentShowKind: kind,
                isCurrentShowVisible: true
            ))
        }

        for kind in [CurrentShowTimeKind.postShow, .ended, .canceled, .postponed] {
            XCTAssertFalse(policy.shouldRequestOnCurrentShow(
                authorizationState: .notDetermined,
                hasRequestedPermissionAfterFirstShow: false,
                currentShowKind: kind,
                isCurrentShowVisible: true
            ))
        }

        XCTAssertFalse(policy.shouldRequestOnCurrentShow(
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: false,
            currentShowKind: .before,
            isCurrentShowVisible: false
        ))
        XCTAssertFalse(policy.shouldRequestOnCurrentShow(
            authorizationState: .denied,
            hasRequestedPermissionAfterFirstShow: false,
            currentShowKind: .before,
            isCurrentShowVisible: true
        ))
        XCTAssertFalse(policy.shouldRequestOnCurrentShow(
            authorizationState: .authorized,
            hasRequestedPermissionAfterFirstShow: false,
            currentShowKind: .before,
            isCurrentShowVisible: true
        ))
        XCTAssertFalse(policy.shouldRequestOnCurrentShow(
            authorizationState: .provisional,
            hasRequestedPermissionAfterFirstShow: false,
            currentShowKind: .before,
            isCurrentShowVisible: true
        ))
        XCTAssertFalse(policy.shouldRequestOnCurrentShow(
            authorizationState: .notDetermined,
            hasRequestedPermissionAfterFirstShow: true,
            currentShowKind: .before,
            isCurrentShowVisible: true
        ))
    }

    func testMissedMilestonesAreNotBackfilledWhenShowIsAddedLate() throws {
        let show = try Show(
            name: "夏夜演唱会",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20)
        )

        let requests = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [show], existingRecords: [], now: now
        ).scheduledRequests

        // now = June 15 10:00; show = June 20 20:00. T-14 and T-7 are past.
        XCTAssertEqual(
            requests.map(\.milestone),
            [.threeDaysBefore, .oneDayBefore, .showDayMorning, .showDay, .openingMemory, .afterShow]
        )
        XCTAssertEqual(requests.map(\.fireDate), [
            makeDate(year: 2026, month: 6, day: 17, hour: 20),
            makeDate(year: 2026, month: 6, day: 19, hour: 20),
            makeDate(year: 2026, month: 6, day: 20, hour: 9),
            makeDate(year: 2026, month: 6, day: 20, hour: 17),
            makeDate(year: 2026, month: 6, day: 20, hour: 20),
            makeDate(year: 2026, month: 6, day: 21, hour: 11)
        ])
    }

    func testShowDayReminderUsesStartTimeMinusThreeHours() throws {
        let show = try Show(
            name: "有开场时间的现场",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: makeDate(year: 2026, month: 6, day: 1)
        )

        XCTAssertEqual(
            requests.first(where: { $0.milestone == .showDay })?.fireDate,
            makeDate(year: 2026, month: 6, day: 20, hour: 17)
        )
    }

    func testPostponedShowDayReminderUsesNewDateWithOriginalStartClock() throws {
        let show = try Show(
            name: "延期保留开场时间的现场",
            date: makeDate(year: 2026, month: 6, day: 10),
            startTime: makeDate(year: 2026, month: 6, day: 10, hour: 19)
        )
        show.markPostponed(newDate: makeDate(year: 2026, month: 6, day: 25, hour: 0))

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: makeDate(year: 2026, month: 6, day: 1)
        )

        XCTAssertEqual(
            requests.map(\.milestone),
            [
                .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore,
                .oneDayBefore, .showDayMorning, .showDay, .openingMemory, .afterShow
            ]
        )
        XCTAssertEqual(requests.map(\.fireDate), [
            makeDate(year: 2026, month: 6, day: 11, hour: 20),
            makeDate(year: 2026, month: 6, day: 18, hour: 20),
            makeDate(year: 2026, month: 6, day: 22, hour: 20),
            makeDate(year: 2026, month: 6, day: 24, hour: 20),
            makeDate(year: 2026, month: 6, day: 25, hour: 9),
            makeDate(year: 2026, month: 6, day: 25, hour: 16),
            makeDate(year: 2026, month: 6, day: 25, hour: 19),
            makeDate(year: 2026, month: 6, day: 26, hour: 11)
        ])
    }

    func testCanceledAndUndatedPostponedShowsDoNotScheduleNotifications() throws {
        let canceled = try Show(
            name: "取消现场",
            date: makeDate(year: 2026, month: 6, day: 25),
            startTime: Date()
        )
        canceled.markCanceled()

        let postponedWithoutNewDate = try Show(
            name: "未定延期现场",
            date: makeDate(year: 2026, month: 6, day: 25),
            startTime: Date()
        )
        postponedWithoutNewDate.markPostponed(newDate: nil)

        let scheduler = LocalNotificationScheduler(calendar: calendar)

        XCTAssertEqual(scheduler.futureRequests(for: canceled, now: now), [])
        XCTAssertEqual(scheduler.futureRequests(for: postponedWithoutNewDate, now: now), [])
    }

    @MainActor
    func testNotificationSchedulingStateCanBeStoredLocally() throws {
        let showID = UUID()
        let state = NotificationSchedulingState()
        state.recordPermissionRequest()
        let record = ShowNotificationScheduleRecord(
            showID: showID,
            milestone: .showDay,
            fireDate: makeDate(year: 2026, month: 6, day: 20, hour: 12)
        )

        let container = try ModelContainer(
            for: NotificationSchedulingState.self, ShowNotificationScheduleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.insert(state)
        container.mainContext.insert(record)
        try container.mainContext.save()

        let states = try container.mainContext.fetch(FetchDescriptor<NotificationSchedulingState>())
        let records = try container.mainContext.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())

        XCTAssertEqual(states.first?.hasRequestedPermissionAfterFirstShow, true)
        XCTAssertEqual(records.first?.milestone, .showDay)
    }

    func testNotificationCarriesShowIDAndDestinationInUserInfo() throws {
        let show = try Show(
            name: "深链现场",
            date: makeDate(year: 2026, month: 7, day: 20),
            startTime: makeDate(year: 2026, month: 7, day: 20, hour: 20)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: makeDate(year: 2026, month: 7, day: 1)
        )

        let destinations: [ShowNotificationMilestone: NotificationDeepLink.Destination] = [
            .fourteenDaysBefore: .listen, .sevenDaysBefore: .listen,
            .threeDaysBefore: .listen, .oneDayBefore: .listen,
            .showDayMorning: .home, .showDay: .home,
            .openingMemory: .memoryCreate, .afterShow: .memoryFragments
        ]
        for (milestone, destination) in destinations {
            let request = try XCTUnwrap(requests.first { $0.milestone == milestone })
            XCTAssertEqual(request.userInfo["showID"] as? String, show.id.uuidString)
            XCTAssertEqual(request.userInfo["destination"] as? String, destination.rawValue)
            XCTAssertEqual(
                NotificationDeepLink(userInfo: request.userInfo),
                NotificationDeepLink(showID: show.id, destination: destination)
            )
        }
    }

    func testNotificationRequestKeepsAbsoluteFireDateAcrossDeviceTimeZones() throws {
        let fireDate = makeDate(year: 2027, month: 9, day: 16, hour: 23)
        let request = ScheduledShowNotification(
            showID: UUID(),
            milestone: .showDay,
            fireDate: fireDate,
            title: "提醒",
            body: "现场快开场了"
        ).makeNotificationRequest()

        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.timeZone, TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(trigger.nextTriggerDate(), fireDate)
    }

    func testOnlyExplicitMemoryDestinationsRequireFeaturePresentation() {
        XCTAssertFalse(NotificationDeepLink.Destination.home.requiresFeaturePresentation)
        XCTAssertFalse(NotificationDeepLink.Destination.listen.requiresFeaturePresentation)
        XCTAssertTrue(NotificationDeepLink.Destination.memoryCreate.requiresFeaturePresentation)
        XCTAssertTrue(NotificationDeepLink.Destination.memoryFragments.requiresFeaturePresentation)
    }

    func testDeepLinkParseRejectsInvalidUserInfo() {
        XCTAssertNil(NotificationDeepLink(userInfo: [:]))
        XCTAssertNil(NotificationDeepLink(userInfo: ["showID": "not-a-uuid", "destination": "home"]))
        XCTAssertNil(NotificationDeepLink(userInfo: ["showID": UUID().uuidString, "destination": "unknown"]))
        XCTAssertNil(NotificationDeepLink(userInfo: ["destination": "home"]))
    }

    // MARK: - 节奏与兜底

    /// 当天临时添加、距开场不足 3 小时的现场，过去会一条通知都收不到。
    func testShowAddedInsideThreeHourWindowStillGetsOneReminder() throws {
        let start = makeDate(year: 2026, month: 6, day: 15, hour: 12)
        let show = try Show(
            name: "临时补票的现场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: start
        )

        // now = 10:00, 开场 12:00：T-3h(09:00) 已过。
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        let showDay = try XCTUnwrap(requests.first { $0.milestone == .showDay })
        XCTAssertEqual(showDay.fireDate, makeDate(year: 2026, month: 6, day: 15, hour: 10, minute: 10))
        XCTAssertLessThan(showDay.fireDate, start)
    }

    /// 已经开场之后添加就不再补开场提醒，只留散场后那条。
    func testShowAddedAfterStartDoesNotBackfillShowDayReminder() throws {
        let show = try Show(
            name: "已经开场的现场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 9)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        XCTAssertFalse(requests.contains { $0.milestone == .showDay })
        XCTAssertEqual(requests.map(\.milestone), [.afterShow])
    }

    /// 散场后那条落到记忆碎片，否则点进来回首页会落空。
    func testAfterShowNotificationRoutesToMemoryFragments() throws {
        let show = try Show(
            name: "散场后的现场",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        let afterShow = try XCTUnwrap(requests.first { $0.milestone == .afterShow })
        XCTAssertEqual(afterShow.fireDate, makeDate(year: 2026, month: 6, day: 21, hour: 11))
        XCTAssertEqual(
            NotificationDeepLink(userInfo: afterShow.userInfo),
            NotificationDeepLink(showID: show.id, destination: .memoryFragments)
        )
    }

    func testOpeningMemoryNotificationFiresAtShowStartAndOpensEditor() throws {
        let show = try Show(
            name: "夜航",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        let opening = try XCTUnwrap(requests.first { $0.milestone == .openingMemory })
        XCTAssertEqual(opening.fireDate, makeDate(year: 2026, month: 6, day: 20, hour: 20))
        XCTAssertEqual(opening.title, BSLocalization.text("留下此刻"))
        XCTAssertEqual(
            opening.body,
            BSLocalization.format("%@ 开始了。想留下什么，我们就留一点下来。", "夜航")
        )
        XCTAssertEqual(
            NotificationDeepLink(userInfo: opening.userInfo),
            NotificationDeepLink(showID: show.id, destination: .memoryCreate)
        )
    }

    func testOpeningMemoryDoesNotBackfillWhenAddedInsideWindow() throws {
        let show = try Show(
            name: "到场才添加的现场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 30)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        XCTAssertFalse(requests.contains { $0.milestone == .openingMemory })
    }

    func testOpeningMemoryDoesNotBackfillAfterWindow() throws {
        let show = try Show(
            name: "已经开场一小时的现场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 9)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        XCTAssertFalse(requests.contains { $0.milestone == .openingMemory })
    }

    /// 只有「快开场了」带声音并突破专注模式，其余节点是无声音的普通横幅。
    func testOnlyShowDayReminderIsTimeSensitive() {
        for milestone in ShowNotificationMilestone.allCases {
            let request = ScheduledShowNotification(
                showID: UUID(),
                milestone: milestone,
                fireDate: now,
                title: "标题",
                body: "正文"
            ).makeNotificationRequest()

            if milestone == .showDay {
                XCTAssertEqual(request.content.interruptionLevel, .timeSensitive)
                XCTAssertNotNil(request.content.sound)
            } else {
                XCTAssertEqual(request.content.interruptionLevel, .active)
                XCTAssertNil(request.content.sound)
            }
        }
    }

    /// 同一现场的通知归到一组，等待期里不散落成一串独立横幅。
    func testNotificationsOfSameShowShareThreadIdentifier() throws {
        let show = try Show(
            name: "归组现场",
            date: makeDate(year: 2026, month: 8, day: 1),
            startTime: makeDate(year: 2026, month: 8, day: 1, hour: 19)
        )

        let requests = LocalNotificationScheduler(calendar: calendar)
            .futureRequests(for: show, now: now)
            .map { $0.makeNotificationRequest() }

        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertEqual(Set(requests.map(\.content.threadIdentifier)), [show.id.uuidString])
    }

    func testNotificationBodyDoesNotRepeatItsTitle() throws {
        let show = try Show(
            name: "夜航",
            date: makeDate(year: 2026, month: 8, day: 1),
            startTime: makeDate(year: 2026, month: 8, day: 1, hour: 19),
            venueName: "MAO Livehouse"
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        for request in requests {
            XCTAssertFalse(
                request.body.localizedCaseInsensitiveContains(request.title),
                "\(request.milestone.rawValue): \(request.title) / \(request.body)"
            )
        }
    }

    /// 文案要用上场馆这类具体事实，而不是只插一个现场名。
    func testCopyMentionsVenueWhenAvailable() throws {
        let show = try Show(
            name: "有场馆的现场",
            date: makeDate(year: 2026, month: 8, day: 1),
            startTime: makeDate(year: 2026, month: 8, day: 1, hour: 19),
            city: "上海",
            venueName: "梅赛德斯奔驰文化中心"
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        let showDay = try XCTUnwrap(requests.first { $0.milestone == .showDay })
        XCTAssertTrue(showDay.body.contains("梅赛德斯奔驰文化中心"))

        let morning = try XCTUnwrap(requests.first { $0.milestone == .showDayMorning })
        XCTAssertTrue(morning.body.contains("19:00"))
    }

    /// 缺场馆 / 城市时退回通用句，不能留下空占位。
    func testCopyFallsBackWhenVenueAndCityAreMissing() throws {
        let show = try Show(
            name: "只有名字的现场",
            date: makeDate(year: 2026, month: 8, day: 1),
            startTime: makeDate(year: 2026, month: 8, day: 1, hour: 19)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        for request in requests {
            XCTAssertFalse(request.body.isEmpty)
            XCTAssertFalse(request.body.contains("(null)"))
            XCTAssertFalse(request.body.contains("%@"))
            XCTAssertFalse(request.body.contains("  "))
        }
    }

    func testWaitingPhaseCopyFeelsLikeListeningTogether() throws {
        let show = try Show(
            name: "夜航",
            date: makeDate(year: 2026, month: 8, day: 1),
            startTime: makeDate(year: 2026, month: 8, day: 1, hour: 19)
        )

        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now
        )

        let fourteen = try XCTUnwrap(requests.first { $0.milestone == .fourteenDaysBefore })
        let seven = try XCTUnwrap(requests.first { $0.milestone == .sevenDaysBefore })
        let three = try XCTUnwrap(requests.first { $0.milestone == .threeDaysBefore })
        let one = try XCTUnwrap(requests.first { $0.milestone == .oneDayBefore })

        XCTAssertTrue(fourteen.body.contains("一起听"))
        XCTAssertTrue(seven.body.contains("把歌先听起来"))
        XCTAssertTrue(three.body.contains("再听几首"))
        XCTAssertTrue(one.body.contains("再听一晚"))
    }

    func testNotificationSchedulingIsTimezoneAware() throws {
        // Show is at June 25, 2026 at 20:00 UTC.
        let showDateUTC = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 25, hour: 20
        ).date!
        
        let show = try Show(name: "跨时区通知现场", date: showDateUTC, startTime: Date())
        
        // Scenario A: UTC Calendar
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcScheduler = LocalNotificationScheduler(calendar: utcCalendar)
        let utcRequests = utcScheduler.futureRequests(for: show, now: now)
        
        if let utcT1 = utcRequests.first(where: { $0.milestone == .oneDayBefore }) {
            // T-1 should be June 24 at 20:00 UTC
            let expectedUTCFireDate = DateComponents(
                calendar: utcCalendar,
                timeZone: utcCalendar.timeZone,
                year: 2026, month: 6, day: 24, hour: 20
            ).date!
            XCTAssertEqual(utcT1.fireDate, expectedUTCFireDate, "T-1 fire date should match UTC local hour")
        } else {
            XCTFail("Should find T-1 notification in UTC")
        }
        
        // Scenario B: Shanghai Calendar (GMT+8)
        // June 25 at 20:00 UTC is June 26 at 04:00 AM in Shanghai.
        // Therefore, T-1 should be June 25 at 20:00 Shanghai time (which is June 25 at 12:00 UTC).
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let shanghaiScheduler = LocalNotificationScheduler(calendar: shanghaiCalendar)
        let shanghaiRequests = shanghaiScheduler.futureRequests(for: show, now: now)
        
        if let shanghaiT1 = shanghaiRequests.first(where: { $0.milestone == .oneDayBefore }) {
            let expectedShanghaiFireDate = DateComponents(
                calendar: shanghaiCalendar,
                timeZone: shanghaiCalendar.timeZone,
                year: 2026, month: 6, day: 25, hour: 20
            ).date!
            XCTAssertEqual(shanghaiT1.fireDate, expectedShanghaiFireDate, "T-1 fire date should match Shanghai local hour")
        } else {
            XCTFail("Should find T-1 notification in Shanghai")
        }
    }

    /// 已确认散场的现场即使同时存在后续现场，也要在 portfolio 中保留次日回看。
    func testConfirmedEndedShowKeepsAfterShowAlongsideOtherShows() throws {
        let ended = try Show(
            name: "已落幕的现场",
            date: makeDate(year: 2026, month: 6, day: 14),
            startTime: makeDate(year: 2026, month: 6, day: 14, hour: 20)
        )
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 14, hour: 22))
        let next = try Show(
            name: "下一场",
            date: makeDate(year: 2026, month: 6, day: 25),
            startTime: makeDate(year: 2026, month: 6, day: 25, hour: 19)
        )
        let staleRecord = ShowNotificationScheduleRecord(
            showID: ended.id,
            milestone: .afterShow,
            fireDate: makeDate(year: 2026, month: 6, day: 15, hour: 11)
        )

        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [ended, next],
            existingRecords: [staleRecord],
            now: now
        )

        let afterShow = try XCTUnwrap(
            plan.scheduledRequests.first {
                $0.showID == ended.id && $0.milestone == .afterShow
            }
        )
        XCTAssertEqual(afterShow.fireDate, makeDate(year: 2026, month: 6, day: 15, hour: 11))
        XCTAssertTrue(plan.scheduledRequests.contains { $0.showID == next.id })
    }

    /// afterShowRequest 只管已确认散场的现场；散场时刻已过就不再排。
    func testAfterShowRequestRequiresConfirmedFutureEnd() throws {
        let scheduler = LocalNotificationScheduler(calendar: calendar)

        let upcoming = try Show(
            name: "未散场的现场",
            date: makeDate(year: 2026, month: 6, day: 20),
            startTime: makeDate(year: 2026, month: 6, day: 20, hour: 20)
        )
        XCTAssertNil(scheduler.afterShowRequest(for: upcoming, now: now))

        let longAgo = try Show(
            name: "早就结束的现场",
            date: makeDate(year: 2026, month: 6, day: 1),
            startTime: makeDate(year: 2026, month: 6, day: 1, hour: 20)
        )
        longAgo.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 22))
        XCTAssertNil(scheduler.afterShowRequest(for: longAgo, now: now))

        // 跨午夜散场：按真实 endedAt 的次日 11:00,而不是开场日的次日。
        let pastMidnight = try Show(
            name: "跨午夜散场的现场",
            date: makeDate(year: 2026, month: 6, day: 14),
            startTime: makeDate(year: 2026, month: 6, day: 14, hour: 22)
        )
        pastMidnight.markEnded(at: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 30))
        let request = try XCTUnwrap(scheduler.afterShowRequest(for: pastMidnight, now: now))
        XCTAssertEqual(request.fireDate, makeDate(year: 2026, month: 6, day: 16, hour: 11))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 20, minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
