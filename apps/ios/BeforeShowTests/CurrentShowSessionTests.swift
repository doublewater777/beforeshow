import XCTest
@testable import BeforeShow

final class CurrentShowSessionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 12)
    }

    func testResolveJoinsSelectionAndPhase() throws {
        let tomorrow = try makeShow(name: "明天的现场", day: 16)
        let later = try makeShow(name: "更远的现场", day: 22)

        let session = CurrentShowSession(calendar: calendar)
        let snapshot = session.resolve(
            shows: [later, tomorrow],
            manualSelection: nil,
            now: now
        )

        XCTAssertEqual(snapshot?.show.id, tomorrow.id)
        XCTAssertEqual(snapshot?.phase.kind, .before)
    }

    func testSnapshotDoesNotRequireShowToBeCurrent() throws {
        let a = try makeShow(name: "A", day: 16)
        let b = try makeShow(name: "B", day: 20)
        let session = CurrentShowSession(calendar: calendar)

        let snapshot = session.snapshot(
            for: b,
            now: now
        )

        XCTAssertEqual(snapshot.show.id, b.id)
        XCTAssertEqual(snapshot.phase.kind, .before)
        XCTAssertFalse(session.isCurrent(b, among: [a, b], now: now))
        XCTAssertTrue(session.isCurrent(a, among: [a, b], now: now))
    }

    func testSelectCurrentShowRespectsManualSelection() throws {
        let nearest = try makeShow(name: "近", day: 16)
        let manual = try makeShow(name: "手动", day: 25)
        let selection = CurrentShowSelection(selectedShowID: manual.id)
        let session = CurrentShowSession(calendar: calendar)

        let selected = session.selectCurrentShow(
            from: [nearest, manual],
            manualSelection: selection,
            now: now
        )
        XCTAssertEqual(selected?.id, manual.id)
    }

    func testManualSelectionPolicyRejectsUndatedPostponedAndEndedShows() throws {
        let undatedPostponed = try makeShow(name: "未定延期", day: 16)
        undatedPostponed.markPostponed(newDate: nil)
        let ended = try makeShow(name: "已结束", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 21))
        let session = CurrentShowSession(calendar: calendar)

        XCTAssertFalse(session.isManuallySelectable(undatedPostponed, now: now))
        XCTAssertFalse(session.isManuallySelectable(ended, now: now))
    }

    func testManualSelectionReconcilesAfterShowBecomesIneligible() throws {
        let ended = try makeShow(name: "已结束", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 21))
        let selection = CurrentShowSelection(selectedShowID: ended.id)

        ShowMutationCoordinator.reconcileManualSelection(
            shows: [ended],
            selections: [selection],
            session: CurrentShowSession(calendar: calendar),
            now: now
        )

        XCTAssertNil(selection.selectedShowID)
    }

    private func makeShow(name: String, day: Int) throws -> Show {
        try Show(
            name: name,
            date: makeDate(year: 2026, month: 6, day: day),
            startTime: makeDate(year: 2026, month: 6, day: day, hour: 20)
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
