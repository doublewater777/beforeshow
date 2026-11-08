import XCTest
@testable import BeforeShow

/// 主按钮只放几乎每个人此刻都会做、一下就完成的事（ADR 0049）。
final class HomeCountdownPrimaryActionTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: day, hour: hour).date!
    }

    private func show(day: Int = 15, endDay: Int? = nil) throws -> Show {
        try Show(
            name: "现场",
            date: date(day: day),
            startTime: date(day: day, hour: 20),
            endDate: endDay.map { date(day: $0) },
            endTime: date(day: day, hour: 22)
        )
    }

    private func primary(
        _ show: Show,
        at now: Date,
        hasPlayedSongs: Bool = false,
        hasFutureShow: Bool = false
    ) -> HomeCountdownLockup.PrimaryAction? {
        HomeCountdownLockup.primaryAction(
            timeState: CurrentShowTimeState(show: show, calendar: calendar, now: now),
            now: now,
            hasPlayedSongs: hasPlayedSongs,
            hasFutureShow: hasFutureShow
        )
    }

    func testBeforeShowDayListens() throws {
        let show = try show()
        XCTAssertEqual(primary(show, at: date(day: 1, hour: 10)), .listen)
        XCTAssertEqual(primary(show, at: date(day: 14, hour: 23)), .listen)
    }

    func testShowDayBeforeDoorsShowsRoute() throws {
        XCTAssertEqual(primary(try show(), at: date(day: 15, hour: 10)), .route)
    }

    func testNothingDuringTheShow() throws {
        XCTAssertNil(primary(try show(), at: date(day: 15, hour: 21)))
    }

    func testFestivalLaterDayGoesRouteThenNothing() throws {
        let festival = try show(endDay: 17)
        XCTAssertEqual(primary(festival, at: date(day: 16, hour: 10)), .route)
        XCTAssertNil(primary(festival, at: date(day: 16, hour: 21)))
    }

    func testAfterTheShowReplaysShowSongsOrFallsBackToListen() throws {
        let show = try show()
        show.markEnded(at: date(day: 15, hour: 22))
        let next = date(day: 16, hour: 10)
        XCTAssertEqual(primary(show, at: next, hasPlayedSongs: true), .replayShow)
        XCTAssertEqual(primary(show, at: next, hasPlayedSongs: false), .listen)
    }

    func testAfterRetentionOffersAddShowOnlyWithoutAFutureShow() throws {
        let show = try show(day: 1)
        show.markEnded(at: date(day: 1, hour: 22))
        let later = date(day: 28, hour: 10)
        XCTAssertEqual(primary(show, at: later), .addShow)
        XCTAssertNil(primary(show, at: later, hasFutureShow: true))
    }

    func testUndatedPostponementAsksForTheNewDateAndCanceledHasNothing() throws {
        let postponed = try show()
        postponed.markPostponed(newDate: nil)
        XCTAssertEqual(primary(postponed, at: date(day: 10)), .fillNewDate)

        let dated = try show()
        dated.markPostponed(newDate: date(day: 25))
        XCTAssertEqual(primary(dated, at: date(day: 10)), .listen)

        let canceled = try show()
        canceled.markCanceled()
        XCTAssertNil(primary(canceled, at: date(day: 10)))
    }

    func testOnlyListeningActionsTurnIntoPause() {
        XCTAssertTrue(HomeCountdownLockup.PrimaryAction.listen.playsMusic)
        XCTAssertTrue(HomeCountdownLockup.PrimaryAction.replayShow.playsMusic)
        XCTAssertFalse(HomeCountdownLockup.PrimaryAction.route.playsMusic)
        XCTAssertFalse(HomeCountdownLockup.PrimaryAction.addShow.playsMusic)
        XCTAssertFalse(HomeCountdownLockup.PrimaryAction.fillNewDate.playsMusic)
    }
}
