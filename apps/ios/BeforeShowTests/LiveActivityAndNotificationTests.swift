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

    // MARK: - Helpers

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
