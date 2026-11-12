import XCTest
@testable import BeforeShow

final class ListeningPickFlightTests: XCTestCase {
    private let size = CGSize(width: 402, height: 800)
    private let start = Date(timeIntervalSinceReferenceDate: 7200)
    private lazy var layout = ListeningPickFlight.Layout(albums: 40, current: 30, size: size, isStill: false)

    func testClockEasesToAStopUnderAFingerAndPicksUpAgain() {
        var clock = ListeningPickFlight.Clock(at: start)
        let t0 = clock.time(at: start)
        XCTAssertEqual(clock.time(at: start + 2) - t0, 2, accuracy: 1e-9)

        clock.ease(to: 0, over: 0.25, at: start + 2)
        XCTAssertEqual(clock.time(at: start + 10) - t0, 2.125, accuracy: 1e-9)
        XCTAssertEqual(clock.rate(at: start + 10), 0)

        clock.ease(to: 1, over: 0.6, at: start + 10)
        XCTAssertEqual(clock.time(at: start + 11) - t0, 2.125 + 0.3 + 0.4, accuracy: 1e-9)
    }

    func testPressingHoldsTheCoverAsSeenAndLettingGoPutsItOnShow() {
        for style in [ListeningPickStyle.toss, .feather] {
            var flight = ListeningPickFlight(style: style, at: start)
            let pressed = start + 3
            let (cover, point) = reachableCover(in: flight, seenAt: pressed - ListeningPickFlight.seenAgo)

            flight.press(at: point, in: layout, date: pressed)
            XCTAssertEqual(flight.held, .cover(cover.id), "\(style)")

            let letGo = pressed + 1
            XCTAssertEqual(flight.release(in: layout, date: letGo), cover.album % 40, "\(style)")
            XCTAssertNil(flight.held)
            XCTAssertEqual(flight.caught?.id, cover.id)
        }
    }

    func testTheCaughtCoverGrowsOutOfWhereItWasThenFliesOn() {
        for style in [ListeningPickStyle.toss, .feather] {
            var flight = ListeningPickFlight(style: style, at: start)
            let pressed = start + 3
            let (cover, point) = reachableCover(in: flight, seenAt: pressed - ListeningPickFlight.seenAgo)
            flight.press(at: point, in: layout, date: pressed)
            let letGo = pressed + 1
            guard let album = flight.release(in: layout, date: letGo), let caught = flight.caught else {
                return XCTFail("\(style)")
            }
            let onShowLayout = ListeningPickFlight.Layout(albums: 40, current: album, size: size, isStill: false)
            let time = flight.time(at: letGo, in: onShowLayout)

            let first = flight.onShow(in: onShowLayout, time: time)
            XCTAssertEqual(first.center.x, caught.center.x, accuracy: 0.01, "\(style)")
            XCTAssertEqual(first.center.y, caught.center.y, accuracy: 0.01, "\(style)")
            XCTAssertEqual(first.side, caught.side, accuracy: 0.01, "\(style)")
            XCTAssertEqual(first.facing, 1, "\(style)")
            XCTAssertEqual(first.opacity, 1, "\(style)")
            XCTAssertFalse(flight.covers(in: onShowLayout, time: time).contains { $0.id == cover.id }, "\(style)")

            let settled = flight.onShow(in: onShowLayout, time: time + 3)
            XCTAssertEqual(settled.facing, 0, "\(style)")
        }
    }

    func testLettingGoOverNothingChangesNothing() {
        var flight = ListeningPickFlight(style: .toss, at: start)
        flight.press(at: CGPoint(x: 200, y: size.height * 0.9), in: layout, date: start + 1)
        XCTAssertNil(flight.held)
        XCTAssertNil(flight.release(in: layout, date: start + 2))
        XCTAssertNil(flight.caught)
    }

    func testAnotherAlbumComingOnDropsTheCatch() {
        var flight = ListeningPickFlight(style: .feather, at: start)
        let (_, point) = reachableCover(in: flight, seenAt: start + 3 - ListeningPickFlight.seenAgo)
        flight.press(at: point, in: layout, date: start + 3)
        guard let album = flight.release(in: layout, date: start + 4) else { return XCTFail() }

        flight.show(album, date: start + 4)
        XCTAssertNotNil(flight.caught)
        flight.show(album + 1, date: start + 5)
        XCTAssertNil(flight.caught)
    }

    /// A background cover a finger can land on, and where.
    private func reachableCover(in flight: ListeningPickFlight, seenAt date: Date) -> (ListeningPickFlight.Cover, CGPoint) {
        let time = flight.time(at: date, in: layout)
        for cover in flight.covers(in: layout, time: time).reversed()
        where flight.target(at: cover.center, in: layout, date: date) == .cover(cover.id) {
            return (cover, cover.center)
        }
        XCTFail("no cover in reach")
        return (flight.onShow(in: layout, time: time), .zero)
    }
}
