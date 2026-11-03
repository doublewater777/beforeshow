import XCTest
@testable import BeforeShow

@MainActor
final class ShowDetailStageTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    // MARK: Mood

    func testMoodFollowsEventStatusBeforeTimePhase() {
        XCTAssertEqual(ShowDetailStagePolicy.mood(changeStatus: .canceled, postponedDate: nil, phase: .inactive, dayDistance: 3), .canceled)
        XCTAssertEqual(ShowDetailStagePolicy.mood(changeStatus: .postponed, postponedDate: nil, phase: .inactive, dayDistance: 0), .postponed)
        XCTAssertEqual(
            ShowDetailStagePolicy.mood(changeStatus: .postponed, postponedDate: date(2026, 12, 1), phase: .pre, dayDistance: 28),
            .before(daysToGo: 28),
            "a postponement with a new date counts down to it"
        )
        XCTAssertEqual(ShowDetailStagePolicy.mood(changeStatus: .scheduled, postponedDate: nil, phase: .live, dayDistance: 0), .live)
        XCTAssertEqual(ShowDetailStagePolicy.mood(changeStatus: .scheduled, postponedDate: nil, phase: .ended, dayDistance: -2), .ended)
    }

    func testLampsWarmUpAsShowtimeNears() {
        XCTAssertEqual(ShowDetailStagePolicy.warmLamps(daysToGo: 12), 1)
        XCTAssertEqual(ShowDetailStagePolicy.warmLamps(daysToGo: 1), 2)
        XCTAssertEqual(ShowDetailStagePolicy.warmLamps(daysToGo: 0), 4)
    }

    // MARK: Clock

    func testClockCountsDaysThenMinutesToDoors() {
        let start = date(2026, 11, 6, 21, 30)

        let days = ShowDetailStagePolicy.clock(for: .before(daysToGo: 3), start: start, end: nil, now: date(2026, 11, 3, 9), exact: false, calendar: calendar)
        XCTAssertEqual(days.value, "D-03")

        let today = ShowDetailStagePolicy.clock(for: .before(daysToGo: 0), start: start, end: nil, now: date(2026, 11, 6, 19, 5), exact: false, calendar: calendar)
        XCTAssertEqual(today.value, "02:25")

        let exact = ShowDetailStagePolicy.clock(for: .before(daysToGo: 3), start: start, end: nil, now: date(2026, 11, 3, 9), exact: true, calendar: calendar)
        XCTAssertEqual(exact.value, "21:30")
        XCTAssertEqual(exact.unit, "FRI 11.06")
    }

    func testClockRunsDuringTheShowAndStopsWhenItCannotHappen() {
        let start = date(2026, 11, 6, 21, 30)

        let live = ShowDetailStagePolicy.clock(for: .live, start: start, end: nil, now: date(2026, 11, 6, 23, 44), exact: false, calendar: calendar)
        XCTAssertEqual(live.value, "02:14")

        XCTAssertEqual(ShowDetailStagePolicy.clock(for: .postponed, start: nil, end: nil, now: start, exact: false, calendar: calendar).value, "--:--")
        XCTAssertEqual(ShowDetailStagePolicy.clock(for: .canceled, start: start, end: nil, now: start, exact: false, calendar: calendar).value, "00:00")
    }

    // MARK: Reunions

    func testReunionsCountOnlyShowsAlreadyAttended() throws {
        let past = try makeShow("吟游拓荒", date(2025, 3, 7), artists: ["陈一豪 Clear"])
        let canceled = try makeShow("取消的", date(2025, 6, 1), artists: ["陈一豪 Clear"])
        canceled.markCanceled()
        let upcoming = try makeShow("橘子湾", date(2026, 11, 6), artists: ["陈一豪 Clear", "黄子弘凡"])
        let later = try makeShow("更晚", date(2026, 12, 20), artists: ["黄子弘凡"])

        let reunions = ShowDetailStagePolicy.reunions(for: upcoming, among: [past, canceled, upcoming, later], now: date(2026, 11, 3))

        XCTAssertEqual(reunions.map(\.name), ["陈一豪 Clear", "黄子弘凡"])
        XCTAssertEqual(reunions.map(\.nth), [2, 1])
    }

    // MARK: Helpers

    private func makeShow(_ name: String, _ day: Date, artists: [String]) throws -> Show {
        try Show(
            name: name,
            date: day,
            startTime: day.addingTimeInterval(20 * 3600),
            timeZoneIdentifier: "Asia/Shanghai",
            city: "福州",
            artists: artists.map { ArtistSlot(name: $0) }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
