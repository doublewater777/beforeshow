import XCTest
@testable import BeforeShow

final class TimetableTimePolicyTests: XCTestCase {
    func testCurrentAndUpcomingPreserveParallelSetsAndExactTransitions() {
        let stage = UUID()
        let first = performance(1, stage: stage, start: 10, end: 20)
        let adjacent = performance(2, stage: stage, start: 20, end: 30)
        let parallel = performance(3, start: 20, end: 30)
        let day = TimetableDayTiming(id: UUID(), performances: [parallel, adjacent, first])
        let cases: [(Double, [UUID], [UUID])] = [
            (9, [], [first.id, adjacent.id, parallel.id]),
            (10, [first.id], [adjacent.id, parallel.id]),
            (19, [first.id], [adjacent.id, parallel.id]),
            (20, [adjacent.id, parallel.id], []),
            (30, [], [])
        ]
        for (time, current, upcoming) in cases {
            let facts = TimetableTimePolicy.facts(for: [day], at: date(time))
            XCTAssertEqual(facts.current.map(\.id), current, "at \(time)")
            XCTAssertEqual(facts.upcoming.map(\.id), upcoming, "at \(time)")
        }
        XCTAssertTrue(TimetableTimePolicy.facts(for: [day], at: date(30)).hasEnded)
    }

    func testOvernightMultiDayBoundariesAndIntradayBreak() {
        // Hour zero is 2026-10-03 00:00 UTC. Day 1 ends after midnight;
        // day 2 has different hours and an empty interval between its sets.
        let first = performance(1, start: 22, end: 26)
        let second = performance(2, start: 40, end: 41)
        let last = performance(3, start: 43, end: 44)
        let day1 = TimetableDayTiming(id: UUID(), performances: [first])
        let day2 = TimetableDayTiming(id: UUID(), performances: [last, second])
        let days = [day2, day1]
        let cases: [(Double, UUID?, UUID?, UUID?, Bool)] = [
            (21, nil, day1.id, nil, false),
            (22, day1.id, day2.id, nil, false),
            (25, day1.id, day2.id, nil, false),
            (26, nil, day2.id, day1.id, false),
            (39, nil, day2.id, day1.id, false),
            (40, day2.id, nil, day1.id, false),
            (42, day2.id, nil, day1.id, false),
            (44, nil, nil, day2.id, true),
            (100, nil, nil, day2.id, true)
        ]
        for (time, active, next, ended, final) in cases {
            let facts = TimetableTimePolicy.facts(for: days, at: date(time))
            XCTAssertEqual(facts.activeDayID, active, "at \(time)")
            XCTAssertEqual(facts.nextDayID, next, "at \(time)")
            XCTAssertEqual(facts.lastEndedDayID, ended, "at \(time)")
            XCTAssertEqual(facts.hasEnded, final, "at \(time)")
            XCTAssertEqual(facts.finalEnd, date(44))
        }
        let breakFacts = TimetableTimePolicy.facts(for: days, at: date(42))
        XCTAssertTrue(breakFacts.current.isEmpty)
        XCTAssertEqual(breakFacts.upcoming.map(\.id), [last.id])
    }

    func testOverlapIncludesContainmentAndBothStagesButExcludesAdjacencyAndSelf() {
        let stage = UUID()
        let first = performance(1, stage: stage, start: 10, end: 20)
        let cases: [(TimetablePerformanceTiming, Bool)] = [
            (first, false),
            (performance(2, stage: stage, start: 15, end: 25), true),
            (performance(3, start: 15, end: 25), true),
            (performance(4, start: 11, end: 12), true),
            (performance(5, start: 10, end: 20), true),
            (performance(6, stage: stage, start: 20, end: 30), false),
            (performance(7, start: 1, end: 10), false)
        ]
        for (other, expected) in cases {
            XCTAssertEqual(TimetableTimePolicy.overlaps(first, other), expected)
            XCTAssertEqual(TimetableTimePolicy.overlaps(other, first), expected)
        }
    }

    func testMissingScheduleDoesNotImplyFinalEnd() {
        for days in [[], [TimetableDayTiming(id: UUID(), performances: [])]] {
            let facts = TimetableTimePolicy.facts(for: days, at: date(100))
            XCTAssertTrue(facts.current.isEmpty)
            XCTAssertTrue(facts.upcoming.isEmpty)
            XCTAssertNil(facts.activeDayID)
            XCTAssertNil(facts.nextDayID)
            XCTAssertNil(facts.lastEndedDayID)
            XCTAssertNil(facts.finalEnd)
            XCTAssertFalse(facts.hasEnded)
        }
    }

    private func performance(
        _ id: Int, stage: UUID = UUID(), start: Double, end: Double
    ) -> TimetablePerformanceTiming {
        TimetablePerformanceTiming(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            stageID: stage, startsAt: date(start), endsAt: date(end)
        )
    }

    private func date(_ hour: Double) -> Date {
        Date(timeIntervalSince1970: 1790985600 + hour * 3_600)
    }
}
