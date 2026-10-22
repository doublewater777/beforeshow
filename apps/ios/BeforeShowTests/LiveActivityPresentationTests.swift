import SwiftUI
import UIKit
import XCTest
@testable import BeforeShow

final class LiveActivityPresentationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_605_600)

    func testReminderBeforeFirstSetUsesItsOwnIdentityAndArtwork() throws {
        var state = baseState()
        state.isReminderActive = true
        state.reminderArtistName = "Saved artist"
        state.reminderStageName = "Wind"
        state.reminderStartsAt = start
        state.reminderExpiresAt = start
        state.reminderArtistImageFilename = "saved.jpg"
        state.nextArtistName = "Earlier artist"
        state.nextStageName = "Main"
        state.nextStartsAt = start.addingTimeInterval(-300)
        state.nextArtistImageFilename = "earlier.jpg"
        let content = LiveActivityContent(state: state, isStale: false, now: start.addingTimeInterval(-600))
        XCTAssertEqual(content.title, "Saved artist")
        XCTAssertEqual(content.lineup?.avatar, "saved.jpg")
        XCTAssertEqual(content.lineup?.stage, "Wind")
        XCTAssertEqual(content.next?.artist, "Earlier artist")
        XCTAssertEqual(content.timerInterval.upperBound, start, "Waiting timer must stop at opening")
    }

    func testSameNameAndTimeOnDifferentStagesRemainDistinct() {
        var state = baseState()
        state.isFestivalDayActive = true
        state.isReminderActive = true
        state.reminderArtistName = "Band"
        state.reminderStageName = "Wind"
        state.reminderStartsAt = start
        state.nextArtistName = "Band"
        state.nextStageName = "Main"
        state.nextStartsAt = start
        let content = LiveActivityContent(state: state, isStale: false, now: start.addingTimeInterval(-600))
        XCTAssertEqual(content.next?.stage, "Main")
    }

    func testStaleRetainsScheduledIdentityWithoutClaimingLiveOrEnding() {
        var state = baseState()
        state.currentArtistName = "Band"
        state.currentStageName = "Main"
        state.currentStartsAt = start
        state.currentEndsAt = start.addingTimeInterval(1800)
        state.isFestivalDayActive = true
        let content = LiveActivityContent(state: state, isStale: true, now: start.addingTimeInterval(600))
        XCTAssertEqual(content.kicker, "正在演出")
        XCTAssertEqual(content.title, "Band")
        XCTAssertNotNil(content.progress)
        XCTAssertFalse(content.showsWave)
        XCTAssertNotEqual(content.mode, .ended)
    }

    func testDefaultTrackingBoundaryDoesNotClaimConfirmedDispersal() {
        let state = baseState()
        let content = LiveActivityContent(state: state, isStale: true, now: state.endBoundary)
        XCTAssertEqual(content.kicker, "本次跟踪已结束")
    }

    func testSummaryReportsAdditionalSavedSetsInsteadOfRepeatingNames() throws {
        let perfs = (0..<3).map { index in
            WidgetTimetablePerformance(id: UUID(), artistName: "Band \(index)", stageID: UUID(),
                stageName: "Stage \(index)", startsAt: start, endsAt: start.addingTimeInterval(1800), isInterested: true)
        }
        let reminder = try XCTUnwrap(LiveActivityPlanner.activeReminder(
            in: WidgetTimetableSnapshot(days: [.init(id: UUID(), date: start, performances: perfs)]),
            now: start.addingTimeInterval(-600)))
        XCTAssertEqual(reminder.summary, "另有 2 场想看即将开演")
    }

    func testPlanMaintainsFocusAndCachedReminderIdentityUntilFocusedSetEnds() throws {
        let focused = UUID()
        let perfs = [
            performance(name: "Default", start: -1800, end: 400),
            performance(id: focused, name: "Focused", start: -1800, end: 600),
            performance(name: "Earlier", start: 100, end: 1000),
            performance(name: "Saved", start: 300, end: 1200, interested: true),
            performance(name: "Also saved", start: 500, end: 1300, interested: true)
        ]
        let snapshot = festival(perfs)
        let sources = LiveActivityPlanner.featuredArtistImageSources(
            snapshot: snapshot, now: start, focusedPerformanceID: focused)
        XCTAssertTrue(sources.contains("https://example.com/Saved.jpg"))
        let plan = try XCTUnwrap(LiveActivityTransitionPlanBuilder.buildPlan(
            snapshot: snapshot, now: start, appInstanceID: "device", activityPushToken: "token",
            isProduction: false, version: 1, focusedPerformanceID: focused,
            artistImageFilename: { source in
                source == "https://example.com/Focused.jpg" ? "focused.jpg"
                    : source == "https://example.com/Saved.jpg" ? "saved.jpg" : nil
            }))
        for step in plan.steps where step.scheduledAt < start.addingTimeInterval(600) {
            XCTAssertEqual(step.state.currentArtistName, "Focused")
            XCTAssertEqual(step.state.currentArtistImageFilename, "focused.jpg")
        }
        XCTAssertNotEqual(plan.steps.first {
            $0.scheduledAt >= start.addingTimeInterval(600)
        }?.state.currentArtistName, "Focused")
        let first = try XCTUnwrap(plan.steps.first)
        XCTAssertEqual(first.state.reminderArtistImageFilename, "saved.jpg")
        XCTAssertEqual(first.reminderEvents?.map(\.startsAt),
                       [start.addingTimeInterval(300), start.addingTimeInterval(500)])
        for step in plan.steps {
            let state = try JSONSerialization.jsonObject(with: JSONEncoder().encode(step.state))
            let payload: [String: Any] = ["aps": [
                "timestamp": 1_792_605_600, "event": "update", "content-state": state,
                "alert": ["title": "椅子乐团快开始了", "body": "18:00 开演 · 风舞台", "sound": "default"]
            ]]
            XCTAssertLessThan(try JSONSerialization.data(withJSONObject: payload).count, 4096)
        }
    }

    func testFinalStatesDistinguishFestivalShowAndTrackingAndPreserveOldDecoding() throws {
        var snapshot = festival([])
        snapshot.timetable = nil
        for (explicit, expected) in [(false, "本次跟踪已结束"), (true, "已散场")] {
            snapshot.timing.endTime = explicit ? start.addingTimeInterval(3600) : nil
            let state = LiveActivityPlanner.naturalFinalState(
                snapshot: snapshot, dayStart: start, activityEnd: start.addingTimeInterval(3600), coverFilename: nil)
            XCTAssertEqual(LiveActivityContent(
                state: state, isStale: true, now: start.addingTimeInterval(3600)).kicker, expected)
        }
        snapshot = festival([performance(name: "Band", start: 0, end: 3600)])
        let state = LiveActivityPlanner.naturalFinalState(
            snapshot: snapshot, dayStart: start, activityEnd: start.addingTimeInterval(3600), coverFilename: nil)
        XCTAssertEqual(LiveActivityContent(
            state: state, isStale: true, now: start.addingTimeInterval(3600)).kicker, "今日演出已结束")
        let old = try JSONDecoder().decode(ShowLiveActivityAttributes.ContentState.self,
            from: Data(#"{"showName":"Legacy","startDate":0}"#.utf8))
        XCTAssertNil(old.reminderArtistImageFilename)
        XCTAssertNil(old.reminderCount)
        XCTAssertNil(old.endKind)
        XCTAssertNil(old.hasTimetable)
    }

    func testCrossMidnightEndHasExplicitNextDayAndExpectedTime() {
        var state = baseState()
        state.startDate = Date(timeIntervalSince1970: 1_792_594_800)
        XCTAssertEqual(LiveActivityCopy.expectedEnd(
            state.startDate.addingTimeInterval(7200), state: state), "预计次日 01:00 散场")
        state.currentStartsAt = state.startDate
        state.currentEndsAt = state.startDate.addingTimeInterval(7200)
        state.currentArtistName = "Band"
        XCTAssertEqual(LiveActivityContent(state: state, isStale: false,
            now: state.startDate.addingTimeInterval(60)).timeRange, "23:00–次日 01:00")
    }

    func testLocalizedActivityCopyUsesPluralAndAbsoluteEventTime() {
        let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        let expected: (String, String, String)
        if language.hasPrefix("en") {
            expected = ("1 more saved set starts soon", "2 more saved sets start soon", "Starts at 02:00")
        } else if language == "zh-Hant" {
            expected = ("另有 1 場想看即將開演", "另有 2 場想看即將開演", "02:00 開演")
        } else {
            expected = ("另有 1 场想看即将开演", "另有 2 场想看即将开演", "02:00 开演")
        }
        XCTAssertEqual(LiveActivityCopy.additionalReminders(1), expected.0)
        XCTAssertEqual(LiveActivityCopy.additionalReminders(2), expected.1)
        XCTAssertEqual(LiveActivityCopy.reminderOpening(start, calendar: baseState().startCalendar), expected.2)
    }

    private func performance(
        id: UUID = UUID(), name: String, start offset: TimeInterval,
        end: TimeInterval, interested: Bool = false
    ) -> WidgetTimetablePerformance {
        .init(id: id, artistName: name, stageID: UUID(), stageName: name,
              startsAt: start.addingTimeInterval(offset), endsAt: start.addingTimeInterval(end),
              isInterested: interested, artistImageURL: "https://example.com/\(name).jpg")
    }

    private func festival(_ performances: [WidgetTimetablePerformance]) -> WidgetShowSnapshot {
        .init(showID: UUID(), name: "Festival", coverImageURL: nil,
              timing: .init(date: start, startTime: start.addingTimeInterval(-1800),
                            endDate: nil, endTime: nil, timeZoneSecondsFromGMT: 28800,
                            endTimeZoneSecondsFromGMT: nil, timeZoneIdentifier: "Asia/Taipei",
                            endTimeZoneIdentifier: nil, endedAt: nil, postponedDate: nil, changeStatus: .scheduled),
              generatedAt: start,
              timetable: .init(days: [.init(id: UUID(), date: start, performances: performances)]))
    }

    private func baseState() -> ShowLiveActivityAttributes.ContentState {
        .init(showName: "Festival", startDate: start, endDate: nil,
              lifecycleEnd: start.addingTimeInterval(14400), timeZoneIdentifier: "Asia/Taipei", coverImageFilename: nil)
    }

}
