import XCTest
@testable import BeforeShow

final class FootprintYearsWalkTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 7200)

    func testTheOpeningWalksInAndSlowsIntoTheStrollWithoutStopping() {
        let walk = FootprintYearsWalk(from: 0, start: start, lead: FootprintYearsWalk.openingLead, last: 30)
        XCTAssertEqual(walk.position(at: start), -FootprintYearsWalk.openingLead, accuracy: 1e-9)

        let frame = 1.0 / 60
        let speeds = (0..<360).map { step in
            (walk.position(at: start + Double(step + 1) * frame) - walk.position(at: start + Double(step) * frame)) / frame
        }
        let stroll = 1 / FootprintYearsWalk.strollPace
        // Never stops, never picks up speed again: one motion settling into the stroll.
        XCTAssertTrue(speeds.allSatisfy { $0 >= stroll - 1e-6 })
        XCTAssertTrue(zip(speeds, speeds.dropFirst()).allSatisfy { $1 <= $0 + 1e-9 })
        XCTAssertEqual(speeds.last ?? 0, stroll, accuracy: 0.01)
    }

    func testTheStrollStopsAtTheOldestShow() {
        let walk = FootprintYearsWalk(from: 3, start: start, last: 5)
        XCTAssertEqual(walk.position(at: start + 1.2), 3.5, accuracy: 1e-9)
        XCTAssertEqual(walk.position(at: start + walk.duration + 10), 5, accuracy: 1e-9)
    }

    func testASingleShowStillWalksIn() {
        let walk = FootprintYearsWalk(from: 0, start: start, lead: FootprintYearsWalk.openingLead, last: 0)
        XCTAssertLessThan(walk.position(at: start + 0.3), -0.1)
        XCTAssertEqual(walk.position(at: start + walk.duration), 0, accuracy: 0.01)
    }
}
