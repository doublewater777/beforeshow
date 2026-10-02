import SwiftData
import XCTest
@testable import BeforeShow

/// ADR 0037：通知与倒计时卡推荐这场还没用过的功能。
final class FeatureRecommendationTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(month: 6, day: 15, hour: 10)
    }

    // MARK: - Policy

    func testCandidateSkipsUsedHandledUnavailableAndExhaustedFeatures() {
        let chain: [RecommendedFeature] = [.companion, .widget, .listen]
        var context = FeatureRecommendationContext()
        XCTAssertEqual(FeatureRecommendationPolicy.candidate(from: chain, context: context), .companion)

        context.unavailable = [.companion]
        XCTAssertEqual(FeatureRecommendationPolicy.candidate(from: chain, context: context), .widget)

        context.used = [.widget]
        XCTAssertEqual(FeatureRecommendationPolicy.candidate(from: chain, context: context), .listen)

        context.records[.listen] = FeatureRecommendationRecordSnapshot(exposureDayKeys: [], isHandled: true)
        XCTAssertNil(FeatureRecommendationPolicy.candidate(from: chain, context: context))
    }

    func testFeatureExposedTwoDaysIsSkippedButStaysForTheRestOfToday() {
        var context = FeatureRecommendationContext()
        context.records[.listen] = FeatureRecommendationRecordSnapshot(
            exposureDayKeys: ["2026-06-14", "2026-06-15"],
            isHandled: false
        )
        XCTAssertTrue(FeatureRecommendationPolicy.isEligible(.listen, context: context, todayKey: "2026-06-15"))
        XCTAssertFalse(FeatureRecommendationPolicy.isEligible(.listen, context: context, todayKey: "2026-06-16"))
        XCTAssertFalse(FeatureRecommendationPolicy.isEligible(.listen, context: context))
    }

    func testPlannedExposuresCountTowardTheTwoDayLimit() {
        let context = FeatureRecommendationContext()
        XCTAssertEqual(
            FeatureRecommendationPolicy.candidate(from: [.listen, .companion], context: context, plannedExposures: [.listen: 2]),
            .companion
        )
    }

    func testFeaturesUsedInOtherShowsGoLast() {
        var context = FeatureRecommendationContext()
        context.usedInOtherShows = [.companion]
        XCTAssertEqual(FeatureRecommendationPolicy.candidate(from: [.companion, .widget], context: context), .widget)
    }

    func testFeatureSkippedInTwoConsecutiveShowsIsMutedUntilUsedAgain() {
        let skipped = FeatureRecommendationRecordSnapshot(exposureDayKeys: ["a", "b"], isHandled: false)
        let first = FeatureRecommendationShowFacts(
            showID: UUID(), sortDate: makeDate(month: 5, day: 1), used: [], records: [.companion: skipped]
        )
        let second = FeatureRecommendationShowFacts(
            showID: UUID(), sortDate: makeDate(month: 5, day: 20), used: [], records: [.companion: skipped]
        )
        XCTAssertTrue(FeatureRecommendationPolicy.mutedFeatures(in: [second, first]).contains(.companion))

        let usedLater = FeatureRecommendationShowFacts(
            showID: UUID(), sortDate: makeDate(month: 6, day: 1), used: [.companion], records: [:]
        )
        XCTAssertFalse(FeatureRecommendationPolicy.mutedFeatures(in: [first, second, usedLater]).contains(.companion))
    }

    func testSnapshotMarksCompanionUnavailableWithoutICloud() throws {
        let show = try makeShow(day: 30)
        let snapshot = FeatureRecommendationSnapshot(
            shows: [FeatureRecommendationShowFacts(showID: show.id, sortDate: show.startTime, used: [], records: [:])],
            facts: FeatureUsageFacts(hasInstalledWidget: false, isICloudAvailable: false)
        )
        XCTAssertEqual(snapshot.context(for: show.id).unavailable, [.companion])
    }

    // MARK: - Ledger

    @MainActor
    func testLedgerRecordsExposureOncePerDayAndMarksHandled() throws {
        let container = try ModelContainer(
            for: FeatureRecommendationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let showID = UUID()

        XCTAssertTrue(try FeatureRecommendationLedger.recordExposure(showID: showID, feature: .listen, dayKey: "2026-06-15", in: context))
        XCTAssertFalse(try FeatureRecommendationLedger.recordExposure(showID: showID, feature: .listen, dayKey: "2026-06-15", in: context))
        XCTAssertTrue(try FeatureRecommendationLedger.markHandled(showID: showID, feature: .listen, in: context))
        try context.save()

        let records = try context.fetch(FetchDescriptor<FeatureRecommendationRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.exposureDayKeys, ["2026-06-15"])
        XCTAssertNotNil(records.first?.handledAt)

        try FeatureRecommendationLedger.deleteOrphans(validShowIDs: [], in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FeatureRecommendationRecord>()).isEmpty)
    }

    // MARK: - Notification planning

    func testOnlyCurrentShowGetsAllNodesOtherShowsOnlyShowDay() throws {
        let current = try makeShow(day: 30)
        let other = try makeShow(day: 20)
        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [current, other],
            existingRecords: [],
            currentShowID: current.id,
            now: now
        )
        XCTAssertGreaterThan(plan.scheduledRequests.filter { $0.showID == current.id }.count, 1)
        XCTAssertEqual(plan.scheduledRequests.filter { $0.showID == other.id }.map(\.milestone), [.showDay])
    }

    func testRecommendationNodeIsSkippedWhenNothingIsLeftToRecommend() throws {
        let show = try makeShow(day: 30)
        var context = FeatureRecommendationContext()
        context.used = [.listen, .companion]
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show,
            now: now,
            scope: NotificationScheduleScope(includesAllMilestones: true, recommendations: context)
        )
        let milestones = requests.map(\.milestone)
        XCTAssertFalse(milestones.contains(.fourteenDaysBefore))
        XCTAssertFalse(milestones.contains(.sevenDaysBefore))
        XCTAssertFalse(milestones.contains(.threeDaysBefore))
        XCTAssertTrue(milestones.contains(.oneDayBefore))
    }

    func testFestivalThreeDaysBeforeRecommendsTimetable() throws {
        let show = try makeShow(day: 30, name: "草莓音乐节")
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now)
        let three = try XCTUnwrap(requests.first { $0.milestone == .threeDaysBefore })
        XCTAssertEqual(three.feature, .timetable)
        XCTAssertEqual(three.destination, .timetable)
        let morning = try XCTUnwrap(requests.first { $0.milestone == .showDayMorning })
        XCTAssertEqual(morning.destination, .timetable)
    }

    func testFollowUpTheDayAfterAddingNeedsAtLeastEightDaysAndSkipsTheFourteenDayMark() throws {
        let show = try makeShow(day: 30)
        let scheduler = LocalNotificationScheduler(calendar: calendar)

        show.createdAt = makeDate(month: 6, day: 14, hour: 9)
        let followUp = try XCTUnwrap(
            scheduler.futureRequests(for: show, now: now).first { $0.milestone == .addedFollowUp }
        )
        XCTAssertEqual(followUp.fireDate, makeDate(month: 6, day: 15, hour: 20))
        XCTAssertEqual(followUp.feature, .widget)
        XCTAssertEqual(followUp.destination, .widgetGuide)

        // 次日正好是 T-14：交给 T-14 那条，不重复发。
        show.createdAt = makeDate(month: 6, day: 15, hour: 9)
        XCTAssertFalse(scheduler.futureRequests(for: show, now: now).contains { $0.milestone == .addedFollowUp })

        // 离开场不足 8 天：不发。
        let soon = try makeShow(day: 21)
        soon.createdAt = makeDate(month: 6, day: 14, hour: 9)
        XCTAssertFalse(scheduler.futureRequests(for: soon, now: now).contains { $0.milestone == .addedFollowUp })
    }

    func testMorningMergesIntoShowDayWhenOpeningIsBeforeOnePM() throws {
        let show = try Show(
            name: "午间现场",
            date: makeDate(month: 6, day: 20),
            startTime: makeDate(month: 6, day: 20, hour: 12)
        )
        let milestones = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now).map(\.milestone)
        XCTAssertFalse(milestones.contains(.showDayMorning))
        XCTAssertTrue(milestones.contains(.showDay))
    }

    func testBackfilledShowDayUsesRealRemainingTime() throws {
        let show = try Show(
            name: "临时补票",
            date: makeDate(month: 6, day: 15),
            startTime: makeDate(month: 6, day: 15, hour: 10, minute: 40)
        )
        let reminder = try XCTUnwrap(
            LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now)
                .first { $0.milestone == .showDay }
        )
        XCTAssertTrue(reminder.body.hasPrefix(BSLocalization.format("%lld 分钟后开场", Int64(30))))
    }

    // MARK: - Countdown card

    func testCardKeepsTodaysExposureAndCollapsesOnceHandled() {
        var context = FeatureRecommendationContext()
        context.records[.widget] = FeatureRecommendationRecordSnapshot(exposureDayKeys: ["2026-06-15"], isHandled: false)
        let chain: [RecommendedFeature] = [.companion, .widget, .listen]

        XCTAssertEqual(
            CurrentShowCardRecommendation.resolve(chain: chain, context: context, todayKey: "2026-06-15", todayNotificationFeature: nil),
            .widget
        )

        context.records[.widget]?.isHandled = true
        XCTAssertNil(
            CurrentShowCardRecommendation.resolve(chain: chain, context: context, todayKey: "2026-06-15", todayNotificationFeature: nil)
        )
        XCTAssertEqual(
            CurrentShowCardRecommendation.resolve(chain: chain, context: context, todayKey: "2026-06-16", todayNotificationFeature: nil),
            .companion
        )
    }

    func testCardFollowsTodaysRecommendationNotification() {
        let context = FeatureRecommendationContext()
        XCTAssertEqual(
            CurrentShowCardRecommendation.resolve(
                chain: [.companion, .widget],
                context: context,
                todayKey: "2026-06-15",
                todayNotificationFeature: .listen
            ),
            .listen
        )
    }

    func testCardSlotsFollowLifecycle() throws {
        let far = try makeShow(day: 30)
        XCTAssertEqual(
            CurrentShowCardRecommendation.slot(timeState: CurrentShowTimeState(show: far, calendar: calendar, now: now), hasConfirmedEnd: false),
            .cardFarBefore
        )
        let near = try makeShow(day: 20)
        XCTAssertEqual(
            CurrentShowCardRecommendation.slot(timeState: CurrentShowTimeState(show: near, calendar: calendar, now: now), hasConfirmedEnd: false),
            .cardNearBefore
        )
        let today = try makeShow(day: 15)
        XCTAssertNil(
            CurrentShowCardRecommendation.slot(timeState: CurrentShowTimeState(show: today, calendar: calendar, now: now), hasConfirmedEnd: false)
        )
    }

    func testCardPrimaryActionUsesRouteOnShowDayAndRecommendationAfterConfirmedEnd() throws {
        let today = try makeShow(day: 15)
        let todayState = CurrentShowTimeState(show: today, calendar: calendar, now: now)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: todayState, now: now),
                timeState: todayState,
                hasConfirmedEnd: false,
                hasEndHandler: true,
                hasRouteHandler: true,
                recommendation: .listen
            ),
            .route
        )

        let ended = try makeShow(day: 14)
        ended.markEnded(at: makeDate(month: 6, day: 14, hour: 22))
        let endedState = CurrentShowTimeState(show: ended, calendar: calendar, now: now)
        XCTAssertEqual(
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: endedState, now: now),
                timeState: endedState,
                hasConfirmedEnd: true,
                hasEndHandler: true,
                recommendation: .dispersal
            ),
            .recommendation(.dispersal)
        )
    }

    // MARK: - Links

    func testLiveActivityLinksRoundTripIntoDeepLinks() throws {
        let showID = UUID()
        let url = try XCTUnwrap(BeforeShowOpenURL.make(showID: showID.uuidString, destination: BeforeShowOpenURL.routeDestination))
        XCTAssertEqual(NotificationDeepLink(url: url), NotificationDeepLink(showID: showID, destination: .route))
        XCTAssertEqual(
            NotificationDeepLink.Destination(rawValue: BeforeShowOpenURL.memoryCreateDestination),
            .memoryCreate
        )
        XCTAssertNil(NotificationDeepLink(url: URL(string: "beforeshow://open?show=nope&destination=route")!))
    }

    func testRecommendationNotificationCarriesFeatureForHandledTracking() {
        let link = NotificationDeepLink(showID: UUID(), destination: .companion, feature: .companion)
        XCTAssertEqual(NotificationDeepLink(userInfo: link.userInfo), link)
    }

    // MARK: - Helpers

    private func makeShow(day: Int, name: String = "现场") throws -> Show {
        try Show(
            name: name,
            date: makeDate(month: 6, day: day),
            startTime: makeDate(month: 6, day: day, hour: 20)
        )
    }

    private func makeDate(month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
