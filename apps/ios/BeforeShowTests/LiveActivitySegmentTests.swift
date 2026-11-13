import Foundation
import XCTest
@testable import BeforeShow

/// 长音乐节日按 8h 切段:每段一个实时活动,从开场前 3h 一直覆盖到散场。
final class LiveActivitySegmentTests: XCTestCase {
    // MARK: - Segments

    func testLongFestivalDaySplitsBackwardFromClosing() {
        // 12:00–23:00:覆盖 09:00–23:00 共 14h → 09–15、15–23(最后一段满 8h)
        XCTAssertEqual(
            LiveActivityPlanner.segments(dayStart: date(12), dayEnd: date(23), splitsLongDays: true),
            [segment(9, 15), segment(15, 23)]
        )
        // 09:00–次日 05:00:覆盖 06:00–29:00 共 23h → 三段
        XCTAssertEqual(
            LiveActivityPlanner.segments(dayStart: date(9), dayEnd: date(29), splitsLongDays: true),
            [segment(6, 13), segment(13, 21), segment(21, 29)]
        )
    }

    func testShortDaysAndPlainShowsKeepOneSegment() {
        XCTAssertEqual(
            LiveActivityPlanner.segments(dayStart: date(20), dayEnd: date(22), splitsLongDays: true),
            [segment(17, 22)]
        )
        // 普通现场不拆:跨多天的散场边界仍只保留最后 8h
        XCTAssertEqual(
            LiveActivityPlanner.segments(dayStart: date(10), dayEnd: date(82), splitsLongDays: false),
            [segment(74, 82)]
        )
    }

    // MARK: - Operations

    func testBeforeWindowSchedulesFirstAndNextSegment() throws {
        let snapshot = makeLongFestival()
        let ops = LiveActivityPlanner.operations(
            snapshot: snapshot, now: date(8), existing: [], coverFilename: nil
        )
        XCTAssertEqual(ops, [
            .schedule(try state(snapshot, at: date(9)), segmentEnd: date(15), start: date(9), isOpening: true),
            .schedule(try state(snapshot, at: date(15)), segmentEnd: date(23), start: date(15), isOpening: false),
        ])
    }

    func testUnchangedPendingSegmentsAreKept() throws {
        let snapshot = makeLongFestival()
        let existing = [
            LiveActivityExisting(id: "a", showID: showID(snapshot), segmentEnd: date(15),
                                 isPending: true, state: try state(snapshot, at: date(9))),
            LiveActivityExisting(id: "b", showID: showID(snapshot), segmentEnd: date(23),
                                 isPending: true, state: try state(snapshot, at: date(15))),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: date(8), existing: existing, coverFilename: nil),
            []
        )
    }

    func testFirstSegmentRunsWhileNextStaysPending() throws {
        let snapshot = makeLongFestival()
        let existing = [
            LiveActivityExisting(id: "a", showID: showID(snapshot), segmentEnd: date(15),
                                 isPending: false, state: try state(snapshot, at: date(10))),
            LiveActivityExisting(id: "b", showID: showID(snapshot), segmentEnd: date(23),
                                 isPending: true, state: try state(snapshot, at: date(15))),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: date(10), existing: existing, coverFilename: nil),
            []
        )
    }

    func testHandoverEndsThePreviousSegment() throws {
        let snapshot = makeLongFestival()
        let now = date(15, 1)
        let existing = [
            LiveActivityExisting(id: "a", showID: showID(snapshot), segmentEnd: date(15),
                                 isPending: false, state: try state(snapshot, at: date(14))),
            LiveActivityExisting(id: "b", showID: showID(snapshot), segmentEnd: date(23),
                                 isPending: false, state: try state(snapshot, at: now)),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: now, existing: existing, coverFilename: nil),
            [.end(id: "a")]
        )
    }

    /// 系统拉起预约段有数秒延迟:刚到点仍 pending 时等它激活,不能结束重建。
    func testDueSegmentStillPendingIsLeftToActivate() throws {
        let snapshot = makeLongFestival()
        let existing = [
            LiveActivityExisting(id: "a", showID: showID(snapshot), segmentEnd: date(15),
                                 isPending: false, state: try state(snapshot, at: date(14))),
            LiveActivityExisting(id: "b", showID: showID(snapshot), segmentEnd: date(23),
                                 isPending: true, state: try state(snapshot, at: date(15))),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: date(15).addingTimeInterval(1),
                                           existing: existing, coverFilename: nil),
            [.end(id: "a")]
        )
        // 过了宽限期还没激活:视为失败,重建
        let late = date(15, 2)
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: late, existing: existing, coverFilename: nil),
            [.end(id: "a"), .end(id: "b"), .request(try state(snapshot, at: late), segmentEnd: date(23))]
        )
    }

    /// App 被强杀后不会被唤醒补预约:当天剩余各段一次排好。
    func testEveryRemainingSegmentIsScheduled() throws {
        let snapshot = makeLongFestival(closingHour: 29)
        let operations = LiveActivityPlanner.operations(
            snapshot: snapshot, now: date(8), existing: [], coverFilename: nil
        )
        XCTAssertEqual(operations.compactMap {
            if case .schedule(_, let end, let start, let isOpening) = $0 { return "\(start)-\(end)-\(isOpening)" }
            return nil
        }, [
            "\(date(9))-\(date(13))-true",
            "\(date(13))-\(date(21))-false",
            "\(date(21))-\(date(29))-false",
        ])
    }

    func testHandoverRequestsTheSegmentWhenItWasNeverScheduled() throws {
        let snapshot = makeLongFestival()
        let now = date(15, 30)
        let existing = [
            LiveActivityExisting(id: "a", showID: showID(snapshot), segmentEnd: date(15),
                                 isPending: false, state: try state(snapshot, at: date(14))),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: now, existing: existing, coverFilename: nil),
            [.end(id: "a"), .request(try state(snapshot, at: now), segmentEnd: date(23))]
        )
    }

    /// 旧版本预约的活动带着旧 alert,没有段信息:重新预约。
    func testLegacyPendingActivityIsRescheduled() throws {
        let snapshot = makeLongFestival()
        let existing = [
            LiveActivityExisting(id: "legacy", showID: showID(snapshot),
                                 isPending: true, state: try state(snapshot, at: date(15))),
        ]
        let operations = LiveActivityPlanner.operations(
            snapshot: snapshot, now: date(8), existing: existing, coverFilename: nil
        )
        XCTAssertEqual(operations.first, .end(id: "legacy"))
        XCTAssertEqual(operations.count, 3)
    }

    /// 旧版本创建的进行中活动没有段信息,视为当天最后一段,升级后不重建。
    func testActivityWithoutSegmentCountsAsTheLastSegment() throws {
        let snapshot = makeLongFestival()
        let now = date(16)
        let existing = [
            LiveActivityExisting(id: "legacy", showID: showID(snapshot),
                                 isPending: false, state: try state(snapshot, at: now)),
        ]
        XCTAssertEqual(
            LiveActivityPlanner.operations(snapshot: snapshot, now: now, existing: existing, coverFilename: nil),
            []
        )
    }

    func testRefreshHappensAtTheHandover() {
        XCTAssertEqual(LiveActivityPlanner.nextRefreshDate(snapshot: makeLongFestival(), now: date(13, 30)), date(15))
    }

    // MARK: - Remote plan

    func testRemotePlanEndsTheSegmentAtItsHandover() throws {
        let plan = try XCTUnwrap(buildPlan(makeLongFestival(), now: date(10)))
        XCTAssertEqual(plan.deadline, date(15))
        let last = try XCTUnwrap(plan.steps.last)
        XCTAssertEqual(last.scheduledAt, date(15))
        XCTAssertEqual(last.staleAt, date(15))
        XCTAssertEqual(last.endsActivity, true)
        XCTAssertNotEqual(last.state.isEnded, true, "交接不是散场")
        XCTAssertTrue(plan.steps.allSatisfy { $0.scheduledAt <= date(15) })
    }

    func testRemotePlanOfTheLastSegmentEndsNaturally() throws {
        let plan = try XCTUnwrap(buildPlan(makeLongFestival(), now: date(16)))
        XCTAssertEqual(plan.deadline, date(23))
        let last = try XCTUnwrap(plan.steps.last)
        XCTAssertEqual(last.state.isEnded, true)
        XCTAssertNil(last.endsActivity)
    }

    // MARK: - Helpers

    private func buildPlan(_ snapshot: WidgetShowSnapshot, now: Date) -> LiveActivityBoundedTransitionPlan? {
        LiveActivityTransitionPlanBuilder.buildPlan(
            snapshot: snapshot, now: now, appInstanceID: "device", activityPushToken: "token",
            isProduction: false, version: 1
        )
    }

    private func state(_ snapshot: WidgetShowSnapshot, at date: Date) throws -> ShowLiveActivityAttributes.ContentState {
        try XCTUnwrap(LiveActivityPlanner.desiredState(snapshot: snapshot, now: date, coverFilename: nil)).state
    }

    private func showID(_ snapshot: WidgetShowSnapshot) -> String { snapshot.showID.uuidString }

    private func segment(_ start: Int, _ end: Int) -> LiveActivitySegment {
        LiveActivitySegment(start: date(start), end: date(end))
    }

    /// 12:00–23:00 单日音乐节(date(0) 为台北当日零点);closingHour 延长压轴。
    private func makeLongFestival(closingHour: Int = 23) -> WidgetShowSnapshot {
        let stage = UUID()
        let performances = [(12, 13, "Opener"), (17, 18, "Middle"), (closingHour - 1, closingHour, "Headliner")].map {
            WidgetTimetablePerformance(
                id: UUID(), artistName: $0.2, stageID: stage, stageName: "Main",
                startsAt: date($0.0), endsAt: date($0.1), isInterested: false
            )
        }
        return WidgetShowSnapshot(
            showID: UUID(),
            name: "Long Festival",
            city: "Shanghai",
            venueName: "Park",
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: date(0),
                startTime: date(12),
                endDate: nil,
                endTime: nil,
                timeZoneSecondsFromGMT: 8 * 3_600,
                endTimeZoneSecondsFromGMT: nil,
                timeZoneIdentifier: "Asia/Taipei",
                endTimeZoneIdentifier: nil,
                endedAt: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date(),
            timetable: WidgetTimetableSnapshot(days: [
                WidgetTimetableDay(id: UUID(), date: date(0), performances: performances)
            ])
        )
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_790_956_800 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
