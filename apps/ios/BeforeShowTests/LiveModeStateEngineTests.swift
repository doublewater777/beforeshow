import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class LiveModeStateEngineTests: XCTestCase {
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

    // MARK: - 1. Upcoming Before Festival Starts

    func testUpcomingBeforeFestivalStarts() {
        let p1 = LivePerformanceInput(
            id: UUID(),
            artistName: "The Smile",
            stageID: UUID(),
            stageName: "Green Stage",
            startsAt: date(14, 0),
            endsAt: date(15, 30),
            isInterested: true
        )
        let day = LiveDayInput(id: UUID(), date: date(0, 0), performances: [p1])

        // Current time is 12:00, 2 hours before first performance
        let state = LiveModeStateEngine.calculate(days: [day], now: date(12, 0))

        XCTAssertEqual(state.phase, .upcoming(firstStartsAt: date(14, 0)))
        XCTAssertFalse(state.isLiveOnStage)
        XCTAssertTrue(state.currentPerformances.isEmpty)
        XCTAssertEqual(state.upcomingPerformances.count, 1)
        XCTAssertEqual(state.upcomingPerformances.first?.artistName, "The Smile")
        XCTAssertFalse(state.upcomingPerformances.first?.isStartingSoon ?? true)
    }

    // MARK: - 2. Active Live Performance & Starting Soon

    func testActivePerformanceAndStartingSoonDynamicWeight() {
        let p1 = LivePerformanceInput(
            id: UUID(),
            artistName: "Fontaines D.C.",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(14, 0),
            endsAt: date(15, 0),
            isInterested: false
        )
        let p2 = LivePerformanceInput(
            id: UUID(),
            artistName: "Idles",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(15, 20),
            endsAt: date(16, 30),
            isInterested: true
        )
        let day = LiveDayInput(id: UUID(), date: date(0, 0), performances: [p1, p2])

        // Now is 14:30 (p1 is playing, p2 starts in 50 minutes > 30m)
        var state = LiveModeStateEngine.calculate(days: [day], now: date(14, 30))
        XCTAssertEqual(state.phase, .active)
        XCTAssertTrue(state.isLiveOnStage)
        XCTAssertEqual(state.currentPerformances.count, 1)
        XCTAssertEqual(state.currentPerformances.first?.artistName, "Fontaines D.C.")
        XCTAssertEqual(state.upcomingPerformances.first?.artistName, "Idles")
        XCTAssertFalse(state.upcomingPerformances.first?.isStartingSoon ?? true)

        // Now is 14:55 (p1 still playing, p2 starts in 25 minutes <= 30m -> Starting Soon elevated!)
        state = LiveModeStateEngine.calculate(days: [day], now: date(14, 55))
        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.upcomingPerformances.first?.artistName, "Idles")
        XCTAssertTrue(state.upcomingPerformances.first?.isStartingSoon ?? false, "Starting soon must be elevated within 30 minutes")
    }

    // MARK: - 3. Multi-stage Parallel Sets: Interested Takes Precedence; Objective Otherwise

    func testMultiStageParallelSetsPrioritizeInterestedWithoutGuessingLocation() {
        let mainStageID = UUID()
        let tentStageID = UUID()

        let pMain = LivePerformanceInput(
            id: UUID(),
            artistName: "Arctic Monkeys",
            stageID: mainStageID,
            stageName: "Main Stage",
            startsAt: date(20, 0),
            endsAt: date(21, 30),
            isInterested: false
        )
        let pTent = LivePerformanceInput(
            id: UUID(),
            artistName: "Four Tet",
            stageID: tentStageID,
            stageName: "Electronic Tent",
            startsAt: date(20, 0),
            endsAt: date(22, 0),
            isInterested: true
        )
        let day = LiveDayInput(id: UUID(), date: date(0, 0), performances: [pMain, pTent])

        // Case A: pTent is interested -> Four Tet should be first, even though start times are equal
        var state = LiveModeStateEngine.calculate(days: [day], now: date(20, 30))
        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.currentPerformances.count, 2)
        XCTAssertEqual(state.currentPerformances[0].artistName, "Four Tet")
        XCTAssertEqual(state.currentPerformances[1].artistName, "Arctic Monkeys")

        // Case B: Neither is interested -> Objective ordering by stage name, no location guessing
        let pTentNeutral = LivePerformanceInput(
            id: pTent.id,
            artistName: "Four Tet",
            stageID: tentStageID,
            stageName: "Electronic Tent",
            startsAt: date(20, 0),
            endsAt: date(22, 0),
            isInterested: false
        )
        let neutralDay = LiveDayInput(id: UUID(), date: date(0, 0), performances: [pMain, pTentNeutral])
        state = LiveModeStateEngine.calculate(days: [neutralDay], now: date(20, 30))
        XCTAssertEqual(state.currentPerformances.count, 2)
        // Deterministic objective order: Electronic Tent < Main Stage
        XCTAssertEqual(state.currentPerformances[0].stageName, "Electronic Tent")
        XCTAssertEqual(state.currentPerformances[1].stageName, "Main Stage")
    }

    // MARK: - 4. Multi-day Intermission: Today Ended, Tomorrow Continues

    func testMultiDayIntermissionTransitionsToDayEndedAndTomorrowContinues() {
        // Day 1: 14:00 - 22:00
        let d1p = LivePerformanceInput(
            id: UUID(),
            artistName: "The Cure",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(14, 0),
            endsAt: date(22, 0),
            isInterested: true
        )
        let day1 = LiveDayInput(id: UUID(), date: date(0, 0), performances: [d1p])

        // Day 2: starts next day at 15:00 (+39 hours from base date)
        let d2p = LivePerformanceInput(
            id: UUID(),
            artistName: "New Order",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(39, 0),
            endsAt: date(42, 0),
            isInterested: true
        )
        let day2 = LiveDayInput(id: UUID(), date: date(24, 0), performances: [d2p])

        let days = [day1, day2]

        // At 23:00 (after Day 1 ends at 22:00, before Day 2 starts at 39:00)
        let state = LiveModeStateEngine.calculate(days: days, now: date(23, 0))
        XCTAssertEqual(state.phase, .dayEnded(nextDayStartsAt: date(39, 0)))
        XCTAssertFalse(state.isLiveOnStage)
        XCTAssertTrue(state.currentPerformances.isEmpty)
        XCTAssertEqual(state.upcomingPerformances.first?.artistName, "New Order")
    }

    // MARK: - 5. Final Set Completed -> Fully Ended

    func testFinalDayCompletedEntersFullyEnded() {
        let p = LivePerformanceInput(
            id: UUID(),
            artistName: "LCD Soundsystem",
            stageID: UUID(),
            stageName: "Main Stage",
            startsAt: date(21, 0),
            endsAt: date(23, 0),
            isInterested: true
        )
        let day = LiveDayInput(id: UUID(), date: date(0, 0), performances: [p])

        // At 23:30 (after final set ends at 23:00)
        let state = LiveModeStateEngine.calculate(days: [day], now: date(23, 30))
        XCTAssertEqual(state.phase, .fullyEnded)
        XCTAssertFalse(state.isLiveOnStage)
        XCTAssertTrue(state.currentPerformances.isEmpty)
        XCTAssertTrue(state.upcomingPerformances.isEmpty)
    }

    // MARK: - 6. Timetable Adaptation Builder

    func testTimetableAdaptationBuildsAccurateInputs() throws {
        let p = try TimetablePerformance(
            artistName: "Slowdive",
            startsAt: date(18, 0),
            endsAt: date(19, 15)
        )
        p.isInterested = true
        let stage = try TimetableStage(name: "Shoegaze Stage", performances: [p])
        let day = try TimetableDay(date: date(0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day])

        let inputs = LiveModeStateEngine.buildInputs(from: timetable)
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].performances.count, 1)
        XCTAssertEqual(inputs[0].performances[0].artistName, "Slowdive")
        XCTAssertEqual(inputs[0].performances[0].stageName, "Shoegaze Stage")
        XCTAssertTrue(inputs[0].performances[0].isInterested)

        // Calculate state with built inputs
        let state = LiveModeStateEngine.calculate(days: inputs, now: date(18, 30))
        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.currentPerformances.first?.artistName, "Slowdive")
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        Date(timeIntervalSince1970: 1790956800 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
