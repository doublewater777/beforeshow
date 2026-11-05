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

    // MARK: Lights

    func testRigRunsCuesInsteadOfSwinging() {
        let palette: [SIMD3<Double>] = [SIMD3(1, 0.2, 0.2), SIMD3(0.2, 0.4, 1)]
        func frame(_ t: Double) -> BSStageFrame {
            BSStageChoreography.frame(at: t, palette: palette)
        }
        var held = 0, chased = 0, dark = 0, lifted = 0, uplit = 0, lasers = 0, alternating = 0
        var previous = frame(0)
        for step in 1...Int(BSStageChoreography.programmeLength(energy: 1) / 0.05) {
            let t = Double(step) * 0.05
            let current = frame(t)
            XCTAssertEqual(current, frame(t))
            let beams = current.truss
            for beam in beams + current.deck {
                XCTAssertLessThanOrEqual(abs(beam.pan), 30)
                XCTAssert((0...1).contains(beam.intensity))
            }
            // Heads move fast on a snap but never teleport.
            for (now, before) in [(beams, previous.truss), (current.deck, previous.deck)] {
                XCTAssertLessThan(zip(now, before).map { abs($0.pan - $1.pan) }.max()!, 8, "at \(t)")
            }
            if zip(beams, previous.truss).allSatisfy({ abs($0.pan - $1.pan) < 0.001 }) { held += 1 }
            if beams.map(\.intensity).max()! - beams.map(\.intensity).min()! > 0.5 { chased += 1 }
            if beams.allSatisfy({ $0.intensity < 0.1 }) { dark += 1 }
            if beams.contains(where: { $0.tilt < 0.6 }) { lifted += 1 }
            if current.deck.contains(where: { $0.intensity > 0.8 }) { uplit += 1 }
            if current.laser.intensity > 0.5 { lasers += 1 }
            if beams.allSatisfy({ $0.intensity > 0.5 }), Set(beams.map { "\($0.rgb)" }).count > 1 { alternating += 1 }
            previous = current
        }
        XCTAssertGreaterThan(held, 20, "looks hold still between moves")
        XCTAssertGreaterThan(chased, 20, "a chase lights one head at a time")
        XCTAssertGreaterThan(dark, 3, "a blackout before the hit")
        XCTAssertGreaterThan(lifted, 10, "heads lift out over the crowd")
        XCTAssertGreaterThan(uplit, 20, "deck lights fan up")
        XCTAssertGreaterThan(lasers, 20, "lasers open on the hit")
        XCTAssertGreaterThan(alternating, 20, "colours alternate along the rig")
    }

    func testRigWarmsUpAsTheShowNears() {
        let palette: [SIMD3<Double>] = [SIMD3(1, 0.2, 0.2), SIMD3(0.2, 0.4, 1)]
        let preset = (0..<200).map { BSStageChoreography.frame(at: Double($0) * 0.25, palette: palette, energy: 0.1) }
        // A week out: one still look, nothing sweeping, no lasers.
        XCTAssertEqual(Set(preset.map { $0.truss.map(\.pan) }).count, 1)
        XCTAssert(preset.allSatisfy { $0.laser.intensity == 0 })
        // Show day: the programme moves, but the lasers wait for the start.
        let showDay = (0..<400).map { BSStageChoreography.frame(at: Double($0) * 0.25, palette: palette, energy: 0.85) }
        XCTAssertGreaterThan(Set(showDay.map { $0.truss.map(\.pan) }).count, 10)
        XCTAssert(showDay.allSatisfy { $0.laser.intensity == 0 })
        XCTAssertLessThan(BSStageChoreography.programmeLength(energy: 0.1), BSStageChoreography.programmeLength(energy: 0.85))
    }

    func testStageEnergyFollowsTheCountdown() {
        let start = date(2026, 11, 20, 20)
        func energy(_ now: Date) -> Double {
            HomeStageEnergy.energy(phase: .pre, start: start, now: now, calendar: calendar)
        }
        XCTAssertEqual(energy(date(2026, 11, 1, 12)), 0.1)
        XCTAssertEqual(energy(date(2026, 11, 16, 12)), 0.35)
        XCTAssertEqual(energy(date(2026, 11, 19, 23)), 0.55)
        XCTAssertEqual(energy(date(2026, 11, 20, 12)), 0.7)
        XCTAssertEqual(energy(date(2026, 11, 20, 18)), 0.85)
        XCTAssertEqual(HomeStageEnergy.energy(phase: .live, start: start, now: start, calendar: calendar), 1)
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
