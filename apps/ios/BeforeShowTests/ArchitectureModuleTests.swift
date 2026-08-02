import XCTest
@testable import BeforeShow

/// Light coverage for architecture-deepening modules (A–F): snapshot seam,
/// end policy without a separate phase arg, cover lifecycle is in
/// `ShowCoverLifecycleTests`.
final class ArchitectureModuleTests: XCTestCase {
    func testHomeHeroSnapshotFoldsPhaseAndTimeState() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "快照现场", date: start, startTime: start)
        // Same calendar day, one hour before doors: kind is `.today`, phase folds to `.pre`.
        let before = start.addingTimeInterval(-3_600)
        let snapshot = HomeHeroSnapshot(show: show, now: before)

        XCTAssertEqual(snapshot.timeState.kind, .today)
        XCTAssertEqual(snapshot.phase, .pre)
        XCTAssertEqual(snapshot.now, before)

        let daysEarlier = start.addingTimeInterval(-3 * 86_400)
        let preSnapshot = HomeHeroSnapshot(show: show, now: daysEarlier)
        XCTAssertEqual(preSnapshot.timeState.kind, .before)
        XCTAssertEqual(preSnapshot.phase, .pre)
    }

    func testHomeHeroSnapshotInactiveWhenCanceled() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "取消现场", date: start, startTime: start)
        show.markCanceled()
        let snapshot = HomeHeroSnapshot(show: show, now: start)

        XCTAssertEqual(snapshot.timeState.kind, .canceled)
        XCTAssertEqual(snapshot.phase, .inactive)
    }

    func testEndPolicyDerivesPhaseInternally() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "可落幕", date: start, startTime: start)
        let afterEstimated = start.addingTimeInterval(5 * 3_600)
        let state = CurrentShowTimeState(show: show, now: afterEstimated)

        XCTAssertEqual(state.kind, .postShow)
        XCTAssertTrue(
            CurrentShowEndPolicy.canRecordEnd(show: show, timeState: state, now: afterEstimated)
        )
    }

    func testFollowUpPolicyExcludesCurrentAndPast() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let past = try Show(name: "过去", date: now.addingTimeInterval(-86_400), startTime: now.addingTimeInterval(-86_400))
        let current = try Show(name: "当前", date: now, startTime: now)
        let later = try Show(name: "之后", date: now.addingTimeInterval(86_400), startTime: now.addingTimeInterval(86_400))

        let result = CurrentShowFollowUpPolicy.laterShows(
            from: [past, current, later],
            excluding: current.id,
            now: now
        )
        XCTAssertEqual(result.map(\.name), ["之后"])
    }
}
