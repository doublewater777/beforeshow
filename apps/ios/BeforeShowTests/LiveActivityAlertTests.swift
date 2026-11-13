import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

/// 预约启动的实时活动一定会弹 alert:开场段由它说「快开场了」,本地那条不再重复;
/// 分段交接静音、只说下一场。
final class LiveActivityAlertTests: XCTestCase {
    // MARK: - Alert copy

    func testOpeningAlertSpeaksForTheThreeHourReminder() {
        let snapshot = makeSnapshot(start: date(20), end: date(23))
        let alert = LiveActivityAlertCopy.opening(snapshot: snapshot, opening: date(20), start: date(17))
        XCTAssertEqual(alert.title, "快开场了")
        XCTAssertEqual(alert.body, "Night Show\n20:00 开场 · Arena。还有 3 小时，准备出门。")
    }

    func testOpeningAlertUsesTheRealLeadWhenTheEightHourCapShortensIt() {
        let snapshot = makeSnapshot(start: date(20), end: date(27))
        let alert = LiveActivityAlertCopy.opening(snapshot: snapshot, opening: date(20), start: date(19))
        XCTAssertEqual(alert.body, "Night Show\n1 小时后开场 · Arena。别错过开场。")
    }

    func testHandoverAlertNamesTheNextSet() {
        var state = baseState()
        state.nextArtistName = "Middle"
        state.nextStageName = "Main"
        state.nextStartsAt = date(17)
        let alert = LiveActivityAlertCopy.handover(state: state)
        XCTAssertEqual(alert.title, "下一场")
        XCTAssertEqual(alert.body, "Middle · 17:00 开演 · Main")
    }

    /// 交接是技术边界,不是换场:有人在演时说正在演出的那一场。
    func testHandoverAlertPrefersTheSetOnStage() {
        var state = baseState()
        state.currentArtistName = "Long Set"
        state.currentStageName = "Main"
        state.nextArtistName = "Later"
        state.nextStartsAt = date(19)
        let alert = LiveActivityAlertCopy.handover(state: state)
        XCTAssertEqual(alert.title, "正在演出")
        XCTAssertEqual(alert.body, "Long Set · Main")
    }

    func testHandoverAlertFallsBackToTheCurrentSet() {
        var state = baseState()
        state.currentArtistName = "Headliner"
        state.currentStageName = "Main"
        let alert = LiveActivityAlertCopy.handover(state: state)
        XCTAssertEqual(alert.title, "正在演出")
        XCTAssertEqual(alert.body, "Headliner · Main")
    }

    // MARK: - Opening coverage

    func testCoverageRecordsTheScheduledOpening() {
        let coverage = makeCoverage()
        let show = UUID()
        XCTAssertTrue(coverage.reconcile(liveShowID: show, coveredOpening: date(17), now: date(10)))
        XCTAssertEqual(coverage.coveredShowIDs(now: date(10)), [show])
        XCTAssertFalse(coverage.reconcile(liveShowID: show, coveredOpening: date(17), now: date(11)))
    }

    func testCoverageIsReleasedWhenTheOpeningIsNoLongerScheduled() {
        let coverage = makeCoverage()
        let show = UUID()
        coverage.reconcile(liveShowID: show, coveredOpening: date(17), now: date(10))
        XCTAssertTrue(coverage.reconcile(liveShowID: show, coveredOpening: nil, now: date(12)))
        XCTAssertEqual(coverage.coveredShowIDs(now: date(12)), [])
    }

    /// 实时活动已经开始(alert 已响),之后不能让本地通知补发一条。
    func testCoverageOutlivesTheOpeningItSpokeFor() {
        let coverage = makeCoverage()
        let show = UUID()
        coverage.reconcile(liveShowID: show, coveredOpening: date(17), now: date(10))
        XCTAssertFalse(coverage.reconcile(liveShowID: show, coveredOpening: nil, now: date(17, 30)))
        XCTAssertEqual(coverage.coveredShowIDs(now: date(17, 30)), [show])
        coverage.reconcile(liveShowID: nil, coveredOpening: nil, now: date(17 + 49))
        XCTAssertEqual(coverage.coveredShowIDs(now: date(17 + 49)), [])
    }

    func testCoverageMovesWithTheLiveActivityShow() {
        let coverage = makeCoverage()
        let first = UUID()
        let second = UUID()
        coverage.reconcile(liveShowID: first, coveredOpening: date(17), now: date(10))
        coverage.reconcile(liveShowID: second, coveredOpening: date(40), now: date(11))
        XCTAssertEqual(coverage.coveredShowIDs(now: date(11)), [second])
    }

    // MARK: - Notification portfolio

    func testCoveredShowKeepsItsOpeningMarkerButIsNotScheduledTwice() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(name: "现场", date: date(24), startTime: date(44))
        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [show], existingRecords: [], currentShowID: show.id,
            liveActivityOpenings: [show.id], now: date(10)
        )
        XCTAssertFalse(plan.scheduledRequests.contains { $0.milestone == .showDay })
        XCTAssertTrue(plan.modelRequests.contains { $0.milestone == .showDay }, "开场标记留着,开演前不会被补发")

        let uncovered = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [show], existingRecords: [], currentShowID: show.id, now: date(10)
        )
        XCTAssertTrue(uncovered.scheduledRequests.contains { $0.milestone == .showDay })
    }

    // MARK: - Helpers

    private func makeCoverage() -> LiveActivityOpeningCoverage {
        let suite = "LiveActivityAlertTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return LiveActivityOpeningCoverage(defaults: UserDefaults(suiteName: suite)!)
    }

    private func baseState() -> ShowLiveActivityAttributes.ContentState {
        ShowLiveActivityAttributes.ContentState(
            showName: "Long Festival",
            startDate: date(12),
            timeZoneSecondsFromGMT: 0,
            timeZoneIdentifier: "UTC",
            coverImageFilename: nil
        )
    }

    private func makeSnapshot(start: Date, end: Date) -> WidgetShowSnapshot {
        WidgetShowSnapshot(
            showID: UUID(),
            name: "Night Show",
            city: "Shanghai",
            venueName: "Arena",
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: date(0),
                startTime: start,
                endDate: nil,
                endTime: end,
                timeZoneSecondsFromGMT: 0,
                endTimeZoneSecondsFromGMT: nil,
                timeZoneIdentifier: "UTC",
                endTimeZoneIdentifier: nil,
                endedAt: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date()
        )
    }

    /// date(0) 为 UTC 当日零点。
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_790_985_600 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
