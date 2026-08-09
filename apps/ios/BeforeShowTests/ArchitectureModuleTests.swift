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

    func testCountdownPresentationAsksBeforeAnnouncingUnconfirmedEnd() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "等待确认的现场", date: start, startTime: start)
        let state = CurrentShowTimeState(
            show: show,
            now: start.addingTimeInterval(5 * 3_600)
        )

        XCTAssertEqual(
            HomeCountdownPresentationPolicy.state(for: show, timeState: state, now: start.addingTimeInterval(5 * 3_600)),
            .askingEnd
        )
    }

    func testCountdownPresentationConfirmsOnlyWhenEndedAtExists() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "已经确认的现场", date: start, startTime: start)
        show.markEnded(at: start.addingTimeInterval(5 * 3_600))
        let now = start.addingTimeInterval(5 * 3_600 + 60)
        let state = CurrentShowTimeState(show: show, now: now)

        XCTAssertEqual(
            HomeCountdownPresentationPolicy.state(for: show, timeState: state, now: now),
            .confirmedEnded
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

    func testImportedDraftWithoutStartTimeStaysUnconfirmed() throws {
        // Import path must not auto-commit a fallback clock merely because a form appears.
        var draft = ShowDraft(
            name: "识别现场",
            date: Date(timeIntervalSince1970: 2_000_000_000),
            startTime: nil,
            source: .screenshotOCR,
            recognizedFields: [.name]
        )
        XCTAssertNil(draft.startTime)
        XCTAssertFalse(draft.recognizedFields.contains(.startTime))
        XCTAssertFalse(draft.hasValidEndTime())

        draft.startTime = Calendar.current.date(
            bySettingHour: 19,
            minute: 30,
            second: 0,
            of: draft.date
        )
        XCTAssertNotNil(draft.startTime)
        XCTAssertTrue(draft.hasValidEndTime())
    }

    func testDraftKeepsEditableVenueAddress() throws {
        var draft = ShowDraft(
            name: "可编辑地点",
            date: Date(timeIntervalSince1970: 2_000_000_000),
            startTime: Date(timeIntervalSince1970: 2_000_000_000),
            venueAddress: "旧地址",
            source: .manual
        )
        draft.venueAddress = "新地址 1 号"
        let show = try draft.makeShow()
        XCTAssertEqual(show.venueAddress, "新地址 1 号")
        XCTAssertEqual(
            MapDestinationQuery.make(
                venueAddress: show.venueAddress,
                venueName: show.venueName,
                city: show.city,
                showName: show.name
            ),
            "新地址 1 号"
        )
    }
}
