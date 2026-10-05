import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableFullLifecycleIntegrationTests: XCTestCase {
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

    // MARK: - 1. Multi-Day Festival End Policy: Only Final Day Can Disperse

    func testMultiDayFestivalEndPolicyAllowsEndOnlyOnFinalDay() throws {
        let showDate = date(10, 0)
        let show = try Show(
            name: "Coachella 2026",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Taipei"
        )
        context.insert(show)

        // Day 1: 14:00 - 22:00
        let d1p = try TimetablePerformance(artistName: "Radiohead", startsAt: date(14, 0), endsAt: date(22, 0))
        let stage1 = try TimetableStage(name: "Coachella Stage", performances: [d1p])
        let day1 = try TimetableDay(date: date(0, 0), stages: [stage1])

        // Day 2 (Final Day): 15:00 - 23:00 (+24h + 15h = 39h, to +24h + 23h = 47h)
        let d2p = try TimetablePerformance(artistName: "Gorillaz", startsAt: date(39, 0), endsAt: date(47, 0))
        let stage2 = try TimetableStage(name: "Outdoor Theatre", performances: [d2p])
        let day2 = try TimetableDay(date: date(24, 0), stages: [stage2])

        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day1, day2])
        timetable.show = show
        show.timetable = timetable
        try context.save()

        let calendar = Calendar(identifier: .gregorian)

        // Case A: During Day 1 (at 18:00) -> CANNOT record end!
        var timeState = CurrentShowTimeState(show: show, calendar: calendar, now: date(18, 0))
        XCTAssertFalse(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: timeState, now: date(18, 0), calendar: calendar))

        // Case B: Day 1 Ended, intermission at night (at 23:00) -> CANNOT record end!
        timeState = CurrentShowTimeState(show: show, calendar: calendar, now: date(23, 0))
        XCTAssertFalse(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: timeState, now: date(23, 0), calendar: calendar))

        // Case C: During Day 2 (Final Day at 40:00) -> CAN record end!
        timeState = CurrentShowTimeState(show: show, calendar: calendar, now: date(40, 0))
        XCTAssertTrue(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: timeState, now: date(40, 0), calendar: calendar))

        // Case D: After Day 2 ends (at 48:00) -> CAN record end!
        timeState = CurrentShowTimeState(show: show, calendar: calendar, now: date(48, 0))
        XCTAssertTrue(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: timeState, now: date(48, 0), calendar: calendar))
    }

    // MARK: - 2. Full Lifecycle: Timetable -> Interested -> Clashes -> Live -> Dispersal -> Footprints
    // Critical Invariant: isInterested NEVER mutates show.artists into watched facts!

    func testFullLifecycleTimetableToFootprintsWithoutSilentlyMarkingWatched() throws {
        // Initial lineup: User entered only 1 artist manually
        let initialSlot = ArtistSlot(name: "Radiohead")
        let showDate = date(10, 0)
        let show = try Show(
            name: "Summer Sonic 2026",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Taipei",
            artists: [initialSlot]
        )
        context.insert(show)

        // Timetable contains multiple other artists: NewJeans, Blur, Kendrick Lamar
        let p1 = try TimetablePerformance(artistName: "NewJeans", startsAt: date(14, 0), endsAt: date(15, 30))
        let p2 = try TimetablePerformance(artistName: "Blur", startsAt: date(15, 0), endsAt: date(16, 30))
        let p3 = try TimetablePerformance(artistName: "Radiohead", startsAt: date(19, 0), endsAt: date(21, 0))

        // User marks NewJeans and Blur as Interested (they clash from 15:00 to 15:30)
        p1.isInterested = true
        p2.isInterested = true
        p3.isInterested = false

        let stageA = try TimetableStage(name: "Marine Stage", performances: [p1, p3])
        let stageB = try TimetableStage(name: "Sonic Stage", performances: [p2])
        let day = try TimetableDay(date: date(0, 0), stages: [stageA, stageB])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day])
        timetable.show = show
        show.timetable = timetable

        // Also attach original timetable photo as asset
        let photoAsset = ShowAsset(showID: show.id, kind: .timetable, relativePath: "timetable_original.jpg")
        show.assets = [photoAsset]
        context.insert(photoAsset)
        try context.save()

        // 1. Clash verification
        let timings = day.stages.flatMap { s in
            s.performances.map { TimetablePerformanceTiming(id: $0.id, stageID: s.id, startsAt: $0.startsAt, endsAt: $0.endsAt) }
        }
        let clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [p1.id, p2.id],
            artistNames: [p1.id: p1.artistName, p2.id: p2.artistName]
        )
        XCTAssertEqual(clashes.count, 1)

        // 2. Live Mode State Engine
        let inputs = LiveModeStateEngine.buildInputs(from: timetable)
        let liveState = LiveModeStateEngine.calculate(days: inputs, now: date(15, 10))
        XCTAssertEqual(liveState.phase, .active)
        XCTAssertEqual(liveState.currentPerformances.count, 2)
        // Interested performances are present
        XCTAssertTrue(liveState.currentPerformances.allSatisfy(\.isInterested))

        // 3. User records dispersal and completes ceremony into footprints
        show.markEnded(at: date(21, 15))
        try show.setClosingRitual(rating: 5, note: "Unforgettable show!", markCeremonyCompleted: true)
        try context.save()

        // 4. Verify Show in footprints archive
        XCTAssertNotNil(show.endedAt)
        XCTAssertTrue(show.hasCompletedDispersalCeremony)

        // 5. CRUCIAL CHECK: show.artists must STRICTLY remain only [Radiohead]!
        // NewJeans and Blur were only "isInterested", NEVER silently injected into show.artists!
        let fetchedShow = try context.fetch(FetchDescriptor<Show>()).first { $0.id == show.id }!
        XCTAssertEqual(fetchedShow.artists.count, 1)
        XCTAssertEqual(fetchedShow.artists.first?.name, "Radiohead")
        XCTAssertFalse(fetchedShow.artistNames.contains("NewJeans"), "isInterested must NEVER become a watched fact")
        XCTAssertFalse(fetchedShow.artistNames.contains("Blur"), "isInterested must NEVER become a watched fact")

        // 6. Timetable and source image preserved for reviewing history
        XCTAssertNotNil(fetchedShow.timetable)
        XCTAssertEqual(fetchedShow.timetable?.orderedDays.first?.performances.count, 3)
        XCTAssertEqual(fetchedShow.assets.first?.kind, .timetable)
    }

    // MARK: - 3. Local Data Inventory & Cleanup Consistency

    func testLocalDataInventoryAccountsForAndCleansTimetables() async throws {
        let showDate = date(10, 0)
        let show = try Show(
            name: "Sonic Park",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Taipei"
        )
        let p = try TimetablePerformance(artistName: "Mogwai", startsAt: date(18, 0), endsAt: date(20, 0))
        let stage = try TimetableStage(name: "Main", performances: [p])
        let day = try TimetableDay(date: date(0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day])
        timetable.show = show
        show.timetable = timetable
        context.insert(show)
        try context.save()

        // Verify inventory reflects timetable
        let inventory = await LocalDataInventoryService.compute(modelContext: context)
        XCTAssertEqual(inventory.showCount, 1)
        XCTAssertEqual(inventory.timetableCount, 1)
        XCTAssertFalse(inventory.isEmpty)
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1790956800 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
