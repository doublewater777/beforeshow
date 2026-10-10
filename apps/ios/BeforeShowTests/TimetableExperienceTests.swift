import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableExperienceTests: XCTestCase {
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

    // MARK: - 1. Interested State Persistence

    func testInterestedStateCanBeToggledAndPersistedIndependently() throws {
        let showDate = date(2026, 8, 15, 10, 0)
        let show = try Show(
            name: "Summer Sonic 2026",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(show)

        let perf1 = try TimetablePerformance(
            artistName: "NewJeans",
            startsAt: date(2026, 8, 15, 13, 0),
            endsAt: date(2026, 8, 15, 14, 0)
        )
        let perf2 = try TimetablePerformance(
            artistName: "Blur",
            startsAt: date(2026, 8, 15, 19, 0),
            endsAt: date(2026, 8, 15, 20, 30)
        )
        let stage = try TimetableStage(name: "Marine Stage", performances: [perf1, perf2])
        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Tokyo", days: [day])
        timetable.show = show
        show.timetable = timetable
        context.insert(timetable)
        try context.save()

        XCTAssertFalse(perf1.isInterested)
        XCTAssertFalse(perf2.isInterested)

        // Toggle perf1 to interested
        perf1.isInterested = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimetablePerformance>())
        let fetchedPerf1 = fetched.first { $0.id == perf1.id }!
        let fetchedPerf2 = fetched.first { $0.id == perf2.id }!
        XCTAssertTrue(fetchedPerf1.isInterested)
        XCTAssertFalse(fetchedPerf2.isInterested)

        // Toggle perf1 back
        perf1.isInterested = false
        try context.save()
        XCTAssertFalse(perf1.isInterested)
    }

    // MARK: - 2. Clash Detection

    func testOverlappingInterestedPerformancesProduceClashWarningWithoutBlocking() throws {
        let p1ID = UUID()
        let p2ID = UUID()
        let p3ID = UUID()
        let stage1ID = UUID()
        let stage2ID = UUID()

        let timings = [
            // Stage 1: 18:00 - 19:30
            TimetablePerformanceTiming(id: p1ID, stageID: stage1ID, startsAt: date(2026, 8, 15, 18, 0), endsAt: date(2026, 8, 15, 19, 30)),
            // Stage 2: 19:00 - 20:00 (Overlaps with Stage 1 during 19:00-19:30)
            TimetablePerformanceTiming(id: p2ID, stageID: stage2ID, startsAt: date(2026, 8, 15, 19, 0), endsAt: date(2026, 8, 15, 20, 0)),
            // Stage 1: 20:00 - 21:00 (Adjacent to Stage 2, not overlapping)
            TimetablePerformanceTiming(id: p3ID, stageID: stage1ID, startsAt: date(2026, 8, 15, 20, 0), endsAt: date(2026, 8, 15, 21, 0))
        ]

        let artistNames = [p1ID: "Radiohead", p2ID: "Massive Attack", p3ID: "Portishead"]
        let stageNames = [stage1ID: "Green Stage", stage2ID: "White Stage"]

        // Case A: Neither is interested -> No clash
        var clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [],
            artistNames: artistNames,
            stageNames: stageNames
        )
        XCTAssertTrue(clashes.isEmpty)

        // Case B: Only one is interested -> No clash
        clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [p1ID],
            artistNames: artistNames,
            stageNames: stageNames
        )
        XCTAssertTrue(clashes.isEmpty)

        // Case C: Both overlapping performances are interested -> Clash detected
        clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [p1ID, p2ID],
            artistNames: artistNames,
            stageNames: stageNames
        )
        XCTAssertEqual(clashes.count, 1)
        let clash = clashes[0]
        XCTAssertEqual(clash.artistName, "Radiohead")
        XCTAssertEqual(clash.conflictingArtistName, "Massive Attack")
        XCTAssertEqual(clash.overlapInterval?.start, date(2026, 8, 15, 19, 0))
        XCTAssertEqual(clash.overlapInterval?.end, date(2026, 8, 15, 19, 30))

        // Bidirectional clash map check
        let map = TimetableClashPolicy.clashMap(from: clashes)
        XCTAssertEqual(map[p1ID]?.count, 1)
        XCTAssertEqual(map[p2ID]?.count, 1)
        XCTAssertEqual(map[p1ID]?.first?.conflictingArtistName, "Massive Attack")
        XCTAssertEqual(map[p2ID]?.first?.conflictingArtistName, "Radiohead")

        // Case D: p2 and p3 (adjacent, 20:00 boundary) -> No clash
        clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [p2ID, p3ID],
            artistNames: artistNames,
            stageNames: stageNames
        )
        XCTAssertTrue(clashes.isEmpty, "Adjacent performances must not be considered a clash")
    }

    // MARK: - 3. Period Policy & Answering Now / Up Next / Evening

    func testPeriodPolicyAnswersNowUpNextAndEvening() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let refTime = date(2026, 8, 15, 14, 15) // 14:15 Tokyo

        // Performance happening NOW: 14:00 - 15:00
        let perfNow = (start: date(2026, 8, 15, 14, 0), end: date(2026, 8, 15, 15, 0))
        XCTAssertTrue(TimetablePeriodPolicy.isNow(startsAt: perfNow.start, endsAt: perfNow.end, at: refTime))
        XCTAssertFalse(TimetablePeriodPolicy.isUpNext(startsAt: perfNow.start, at: refTime))
        XCTAssertFalse(TimetablePeriodPolicy.isEvening(startsAt: perfNow.start, timeZone: tokyo))

        // Performance UP NEXT: 15:30 - 16:30 (starts in 75 minutes, <= 2h window)
        let perfNext = (start: date(2026, 8, 15, 15, 30), end: date(2026, 8, 15, 16, 30))
        XCTAssertFalse(TimetablePeriodPolicy.isNow(startsAt: perfNext.start, endsAt: perfNext.end, at: refTime))
        XCTAssertTrue(TimetablePeriodPolicy.isUpNext(startsAt: perfNext.start, at: refTime))
        XCTAssertFalse(TimetablePeriodPolicy.isEvening(startsAt: perfNext.start, timeZone: tokyo))

        // Performance EVENING: 19:30 - 21:00 (starts at 19:30 >= 18:00)
        let perfEvening = (start: date(2026, 8, 15, 19, 30), end: date(2026, 8, 15, 21, 0))
        XCTAssertFalse(TimetablePeriodPolicy.isNow(startsAt: perfEvening.start, endsAt: perfEvening.end, at: refTime))
        XCTAssertFalse(TimetablePeriodPolicy.isUpNext(startsAt: perfEvening.start, at: refTime))
        XCTAssertTrue(TimetablePeriodPolicy.isEvening(startsAt: perfEvening.start, timeZone: tokyo))
        XCTAssertEqual(TimetablePeriodPolicy.dayPart(for: perfEvening.start, timeZone: tokyo), .evening)
    }

    // MARK: - 4. Listening Signals MUST NOT Modify isInterested

    func testListeningSignalsNeverModifyIsInterested() throws {
        let perf = try TimetablePerformance(
            artistName: "King Gizzard & The Lizard Wizard",
            startsAt: date(2026, 8, 15, 16, 0),
            endsAt: date(2026, 8, 15, 17, 30)
        )
        perf.isInterested = false

        let listenedSet: Set<String> = [
            "King Gizzard & The Lizard Wizard",
            "Radiohead"
        ]

        // 1. Check policy detection
        let hasEvidence = TimetableListeningPolicy.hasListeningEvidence(
            artistName: perf.artistName,
            listenedArtistNames: listenedSet
        )
        XCTAssertTrue(hasEvidence)

        // 2. VERIFY STRICT INVARIANT: perf.isInterested has NOT been mutated
        XCTAssertFalse(perf.isInterested, "Listening evidence must NEVER auto-set isInterested")

        // 3. Normalized matching check with punctuation/casing variations
        let messyName = "  king gizzard & the lizard wizard  "
        XCTAssertTrue(TimetableListeningPolicy.hasListeningEvidence(
            artistName: messyName,
            listenedArtistNames: listenedSet
        ))
        XCTAssertFalse(perf.isInterested)
    }

    // MARK: - 5. Multi-day, Multi-stage, Long Artist Names Robustness

    func testMultiDayMultiStageTimetableWithLongArtistNames() throws {
        let tokyo = "Asia/Tokyo"
        let longArtist1 = "King Gizzard & The Lizard Wizard"
        let longArtist2 = "Godspeed You! Black Emperor"
        let longArtist3 = "And So I Watch You From Afar"

        // Day 1
        let d1p1 = try TimetablePerformance(artistName: longArtist1, startsAt: date(2026, 8, 15, 14, 0), endsAt: date(2026, 8, 15, 15, 30))
        let d1p2 = try TimetablePerformance(artistName: longArtist2, startsAt: date(2026, 8, 15, 18, 0), endsAt: date(2026, 8, 15, 19, 30))
        let d1p3 = try TimetablePerformance(artistName: "Toe", startsAt: date(2026, 8, 15, 18, 30), endsAt: date(2026, 8, 15, 19, 45))

        let stageA = try TimetableStage(name: "Mountain Stage", performances: [d1p1, d1p2])
        let stageB = try TimetableStage(name: "Sonic Stage", performances: [d1p3])
        let day1 = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stageA, stageB])

        // Day 2
        let d2p1 = try TimetablePerformance(artistName: longArtist3, startsAt: date(2026, 8, 16, 15, 0), endsAt: date(2026, 8, 16, 16, 0))
        let stageC = try TimetableStage(name: "Rainbow Stage", performances: [d2p1])
        let day2 = try TimetableDay(date: date(2026, 8, 16, 0, 0), stages: [stageC])

        let timetable = try Timetable(timeZoneIdentifier: tokyo, days: [day1, day2])
        XCTAssertEqual(timetable.orderedDays.count, 2)
        XCTAssertEqual(day1.orderedStages.count, 2)
        XCTAssertEqual(day1.performances.count, 3)

        // Mark longArtist2 and Toe as interested on Day 1 -> They overlap
        d1p2.isInterested = true
        d1p3.isInterested = true

        let timings = day1.stages.flatMap { s in
            s.performances.map {
                TimetablePerformanceTiming(id: $0.id, stageID: s.id, startsAt: $0.startsAt, endsAt: $0.endsAt)
            }
        }
        let clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [d1p2.id, d1p3.id],
            artistNames: [d1p2.id: d1p2.artistName, d1p3.id: d1p3.artistName]
        )
        XCTAssertEqual(clashes.count, 1)
        XCTAssertEqual(clashes.first?.artistName, longArtist2)
        XCTAssertEqual(clashes.first?.conflictingArtistName, "Toe")
    }

    // MARK: - 6. Usability without any Interested

    func testTimetableRemainsFullyUsableWithZeroInterestedPerformances() throws {
        let p1 = try TimetablePerformance(artistName: "Oasis", startsAt: date(2026, 8, 15, 14, 0), endsAt: date(2026, 8, 15, 15, 0))
        let p2 = try TimetablePerformance(artistName: "Pulp", startsAt: date(2026, 8, 15, 19, 0), endsAt: date(2026, 8, 15, 20, 30))
        let stage = try TimetableStage(name: "Main Stage", performances: [p1, p2])
        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Tokyo", days: [day])

        // Verify zero interested
        XCTAssertEqual(day.performances.filter(\.isInterested).count, 0)

        // All timetable schedules are accessible
        XCTAssertEqual(timetable.orderedDays.first?.performances.count, 2)
        XCTAssertEqual(timetable.orderedDays.first?.orderedStages.first?.orderedPerformances.count, 2)

        // Period filter still functions perfectly
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let eveningSets = day.performances.filter {
            TimetablePeriodPolicy.matches(startsAt: $0.startsAt, endsAt: $0.endsAt, isInterested: $0.isInterested, filter: .evening, timeZone: tokyo)
        }
        XCTAssertEqual(eveningSets.count, 1)
        XCTAssertEqual(eveningSets.first?.artistName, "Pulp")
    }

    // MARK: - 7. Non-blocking and non-recommending Clashes

    func testClashWarningNeverBlocksOrRecommendsDropping() throws {
        let p1 = try TimetablePerformance(artistName: "The Chemical Brothers", startsAt: date(2026, 8, 15, 20, 0), endsAt: date(2026, 8, 15, 21, 30))
        let p2 = try TimetablePerformance(artistName: "Underworld", startsAt: date(2026, 8, 15, 20, 30), endsAt: date(2026, 8, 15, 22, 0))
        p1.isInterested = true
        p2.isInterested = true

        let timings = [
            TimetablePerformanceTiming(id: p1.id, stageID: UUID(), startsAt: p1.startsAt, endsAt: p1.endsAt),
            TimetablePerformanceTiming(id: p2.id, stageID: UUID(), startsAt: p2.startsAt, endsAt: p2.endsAt)
        ]

        let clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: [p1.id, p2.id],
            artistNames: [p1.id: p1.artistName, p2.id: p2.artistName]
        )
        XCTAssertEqual(clashes.count, 1)

        // Crucial invariant: both performances remain interested simultaneously; neither was dropped!
        XCTAssertTrue(p1.isInterested)
        XCTAssertTrue(p2.isInterested)
    }


    // MARK: - 8. In-Situ Matrix Editing & Stage Migration

    func testInSituPerformanceMutationsAndStageMoving() throws {
        let p1 = try TimetablePerformance(artistName: "Radiohead", startsAt: date(2026, 8, 15, 18, 0), endsAt: date(2026, 8, 15, 19, 0))
        let stage1 = try TimetableStage(name: "Moon Stage", sortOrder: 0, performances: [p1])
        p1.stage = stage1

        let p2 = try TimetablePerformance(artistName: "Massive Attack", startsAt: date(2026, 8, 15, 19, 30), endsAt: date(2026, 8, 15, 20, 30))
        let stage2 = try TimetableStage(name: "Sun Stage", sortOrder: 1, performances: [p2])
        p2.stage = stage2

        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage1, stage2])
        stage1.day = day
        stage2.day = day

        // 1. Shift time by +10 minutes
        p1.shiftTimes(by: 600)
        XCTAssertEqual(p1.startsAt, date(2026, 8, 15, 18, 10))
        XCTAssertEqual(p1.endsAt, date(2026, 8, 15, 19, 10))

        // 2. Move p1 to stage2
        p1.moveTo(stage: stage2)
        XCTAssertEqual(p1.stage?.id, stage2.id)

        // 3. Rename stage
        try stage1.updateName("Earth Stage")
        XCTAssertEqual(stage1.name, "Earth Stage")

        // 4. Update details
        try p1.updateDetails(
            artistName: "The Smile",
            startsAt: date(2026, 8, 15, 18, 30),
            endsAt: date(2026, 8, 15, 19, 45)
        )
        XCTAssertEqual(p1.artistName, "The Smile")
        XCTAssertEqual(p1.startsAt, date(2026, 8, 15, 18, 30))
        XCTAssertEqual(p1.endsAt, date(2026, 8, 15, 19, 45))

        // 5. Add stage to day
        let newStage = try day.addStage(name: "Star Stage")
        XCTAssertEqual(newStage.name, "Star Stage")
        XCTAssertTrue(day.stages.contains { $0.id == newStage.id })
    }

    func testMatrixLayoutYToDateMapping() throws {
        let dayStart = date(2026, 8, 15, 12, 0)
        let perf = try TimetablePerformance(
            artistName: "Artist",
            startsAt: date(2026, 8, 15, 14, 0),
            endsAt: date(2026, 8, 15, 15, 0)
        )
        let stage = try TimetableStage(name: "Main", performances: [perf])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let layout = TimetableMatrixLayout(
            stages: [.init(id: stage.id, name: stage.name, performances: [
                .init(id: perf.id, artistName: perf.artistName, startsAt: perf.startsAt, endsAt: perf.endsAt, isInterested: false)
            ])],
            now: dayStart,
            calendar: cal
        )

        let yStart = layout.y(for: layout.start)
        XCTAssertEqual(yStart, TimetableMatrixLayout.topInset, accuracy: 0.1)

        let mappedStart = layout.date(for: yStart)
        XCTAssertEqual(mappedStart.timeIntervalSince(layout.start), 0, accuracy: 1)

        let oneHourLater = layout.start.addingTimeInterval(3600)
        let yOneHour = layout.y(for: oneHourLater)
        XCTAssertEqual(yOneHour, TimetableMatrixLayout.topInset + 60 * TimetableMatrixLayout.pointsPerMinute, accuracy: 0.1)
        let mappedHour = layout.date(for: yOneHour)
        XCTAssertEqual(mappedHour.timeIntervalSince(oneHourLater), 0, accuracy: 1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components)!
    }
}
