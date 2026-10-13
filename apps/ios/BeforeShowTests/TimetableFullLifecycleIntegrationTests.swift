import Foundation
import SwiftData
import XCTest
import UIKit
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

    func testFailedTimetableReplacementPreservesOriginalFilesAndRemovesPartialImport() async throws {
        let show = try Show(name: "Festival", date: date(0, 0), startTime: date(18, 0))
        let performance = try TimetablePerformance(artistName: "Original Artist", startsAt: date(18, 0), endsAt: date(20, 0))
        let stage = try TimetableStage(name: "Main", performances: [performance])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [TimetableDay(date: date(0, 0), stages: [stage])])
        show.timetable = timetable
        context.insert(show)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { renderer in
            UIColor.red.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let store = ShowAssetMediaStore.shared
        let originalPath = try await store.saveImage(data: data, showID: show.id, kind: .timetable, assetID: UUID())
        let originalURL = try await store.absoluteURL(for: originalPath, showID: show.id, kind: .timetable)
        defer { try? FileManager.default.removeItem(at: originalURL.deletingLastPathComponent().deletingLastPathComponent()) }
        let originalData = try Data(contentsOf: originalURL)
        let asset = ShowAsset(showID: show.id, kind: .timetable, relativePath: originalPath)
        asset.show = show
        context.insert(asset)
        try context.save()
        var draft = TimetableDraft(from: timetable)
        draft.updatePerformance(id: performance.id, artistName: "Replacement Artist", startsAt: date(18, 0), endsAt: date(20, 0))

        let coordinator = TimetableManagementCoordinator()
        let succeeded = await coordinator.commit(
            draft: draft,
            newImagesData: [data, Data("invalid image".utf8)],
            show: show,
            modelContext: context
        )

        XCTAssertFalse(succeeded)
        let reloaded = ModelContext(container)
        let restored = try XCTUnwrap(reloaded.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(restored.timetable?.id, timetable.id)
        XCTAssertEqual(restored.assets.map(\.relativePath), [originalPath])
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: originalURL.deletingLastPathComponent().path), [originalURL.lastPathComponent])

        let retried = await coordinator.commit(draft: draft, newImagesData: [data], show: restored, modelContext: reloaded)
        XCTAssertTrue(retried)
        XCTAssertEqual(restored.timetable?.orderedDays.first?.performances.first?.artistName, "Replacement Artist")
        XCTAssertEqual(restored.assets.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        let replacement = try XCTUnwrap(restored.assets.first)
        let replacementURL = try await store.absoluteURL(for: replacement.relativePath, showID: show.id, kind: .timetable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))
        XCTAssertEqual(try reloaded.fetchCount(FetchDescriptor<Timetable>()), 1)

        await coordinator.deleteTimetable(show: restored, modelContext: reloaded)
        XCTAssertNil(restored.timetable)
        XCTAssertTrue(restored.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementURL.path))
        XCTAssertEqual(try reloaded.fetchCount(FetchDescriptor<Show>()), 1)
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

    func testTimetableKeepsShowLiveBeyondDefaultEstimateAcrossAppAndWidget() throws {
        let show = try lifecycleShow(sessions: [(14, 23)])
        let now = date(20)
        let state = CurrentShowTimeState(show: show, now: now)
        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.endBoundary, date(23))
        XCTAssertEqual(LiveActivityShowResolver().resolve(shows: [show], currentShow: show, now: now)?.id, show.id)
        XCTAssertTrue(FootprintArchiveBuilder.make(shows: [show], now: now).shows.isEmpty)
        let snapshot = WidgetShowSnapshot(show: show, generatedAt: now)
        XCTAssertEqual(CurrentShowTimeState(timing: snapshot.timing, now: now).kind, .today)
        let reminders = LocalNotificationScheduler().futureRequests(for: show, now: date(10))
        XCTAssertEqual(reminders.first { $0.milestone == .postShowRitual }?.fireDate, date(23, 15))
    }

    func testChangedDatesSuspendOldTimetableWithoutMovingPerformances() throws {
        for postponement in [true, false] {
            let show = try lifecycleShow(sessions: [(14, 23)])
            let performance = try XCTUnwrap(show.timetable?.orderedDays.first?.performances.first)
            performance.isInterested = true
            if postponement {
                show.markPostponed(newDate: date(24 * 30))
            } else {
                var draft = ShowDraft(show: show)
                draft.date = date(24 * 30)
                try show.apply(draft)
            }
            XCTAssertEqual(performance.startsAt, date(14))
            XCTAssertNil(CurrentShowLiveTimetablePolicy.resolve(for: show, now: date(15)))
            XCTAssertNil(WidgetShowSnapshot(show: show, generatedAt: date(10)).timetable)
            XCTAssertFalse(LocalNotificationScheduler().futureRequests(for: show, now: date(10))
                .contains { $0.milestone == .interestedPerformance })
        }
    }

    func testFinalDayUpcomingCannotConfirmWholeShowEnd() throws {
        let show = try lifecycleShow(sessions: [(14, 23), (39, 47)], endDay: 24)
        let now = date(36)
        let state = CurrentShowTimeState(show: show, now: now)
        XCTAssertFalse(CurrentShowEndPolicy.canRecordEnd(show: show, timeState: state, now: now))
        XCTAssertFalse(CurrentShowEndPolicy.isValidConfirmedEnd(date(36), for: show, now: date(48)))
        XCTAssertTrue(CurrentShowEndPolicy.isValidConfirmedEnd(date(40), for: show, now: date(48)))
    }

    func testTimetableRestDayDoesNotBecomeDailyLiveSession() throws {
        let show = try lifecycleShow(sessions: [(14, 23), (63, 71)], endDay: 48)
        let state = CurrentShowTimeState(show: show, now: date(36))
        XCTAssertEqual(state.kind, .dayEnded)
        XCTAssertNil(LiveActivityPlanner.desiredState(
            snapshot: WidgetShowSnapshot(show: show, generatedAt: date(36)), now: date(36), coverFilename: nil))
        XCTAssertTrue(FootprintArchiveBuilder.make(shows: [show], now: date(36)).shows.isEmpty)
    }

    func testNonCurrentShowOnlySchedulesShowDayDespiteInterestedPerformances() throws {
        let show = try lifecycleShow(sessions: [(14, 23)])
        show.timetable?.orderedDays.first?.performances.first?.isInterested = true
        let scheduler = LocalNotificationScheduler()
        XCTAssertTrue(scheduler.futureRequests(for: show, now: date(6), scope: .all)
            .contains { $0.milestone == .interestedPerformance })
        XCTAssertEqual(scheduler.futureRequests(for: show, now: date(6), scope: .showDayOnly).map(\.milestone), [.showDay])
    }

    func testPostponedTimetableRequiresSavedConfirmationAfterDatesAreCorrected() throws {
        let show = try lifecycleShow(sessions: [(14, 23)])
        let timetable = try XCTUnwrap(show.timetable)
        let day = try XCTUnwrap(timetable.orderedDays.first)
        show.markPostponed(newDate: date(24))
        XCTAssertFalse(timetable.confirmDates(for: show))
        try timetable.updateDayDate(day, to: date(24))
        XCTAssertNil(show.lifecycleTimetable)
        try context.save()
        let reloadedContext = ModelContext(container)
        let reloaded = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertNil(reloaded.lifecycleTimetable)
        let restoredTimetable = try XCTUnwrap(reloaded.timetable)
        XCTAssertTrue(restoredTimetable.confirmDates(for: reloaded))
        try reloadedContext.save()
        XCTAssertEqual(CurrentShowTimeState(show: reloaded, now: date(44)).kind, .today)
        XCTAssertEqual(CurrentShowTimeState(show: reloaded, now: date(44)).endBoundary, date(47))
    }

    func testTimetableVenueZoneWinsOverDeviceZoneAndConfirmedEndWinsOverSets() throws {
        let show = try lifecycleShow(sessions: [(14, 23)])
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let state = CurrentShowTimeState(show: show, calendar: deviceCalendar, now: date(6))
        XCTAssertEqual(state.dayDistance, 0)
        let timetable = try XCTUnwrap(show.timetable)
        timetable.orderedDays.first?.performances.first?.isInterested = true
        let requests = LocalNotificationScheduler(calendar: deviceCalendar).futureRequests(for: show, now: date(6))
        XCTAssertTrue(try XCTUnwrap(requests.first { $0.milestone == .interestedPerformance }).body.contains("14:00 - 23:00"))
        show.markEnded(at: date(20))
        let snapshot = WidgetShowSnapshot(show: show, generatedAt: date(21))
        XCTAssertEqual(CurrentShowTimeState(timing: snapshot.timing, calendar: deviceCalendar, now: date(21)).kind, .postShow)
        XCTAssertNil(LiveActivityPlanner.desiredState(snapshot: snapshot, now: date(21), coverFilename: nil))
    }

    func testTimetableCannotOverrideLaterExplicitClosing() throws {
        let show = try lifecycleShow(sessions: [(14, 20)])
        var draft = ShowDraft(show: show)
        draft.endTime = date(23)
        try show.apply(draft)
        let now = date(21)
        XCTAssertEqual(CurrentShowTimeState(show: show, now: now).kind, .today)
        XCTAssertNil(CurrentShowLiveTimetablePolicy.resolve(for: show, now: now))
        let activity = LiveActivityPlanner.desiredState(
            snapshot: WidgetShowSnapshot(show: show, generatedAt: now), now: now, coverFilename: nil)
        XCTAssertEqual(activity?.activityEnd, date(23))
    }

    private func lifecycleShow(sessions: [(Int, Int)], endDay: Int? = nil) throws -> Show {
        let show = try Show(name: "Festival", date: date(0), startTime: date(10),
                            endDate: endDay.map { date($0) }, timeZoneIdentifier: "Asia/Taipei")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let days = try sessions.map { start, end in
            let performance = try TimetablePerformance(artistName: "Artist", startsAt: date(start), endsAt: date(end))
            let stage = try TimetableStage(name: "Main", performances: [performance])
            return try TimetableDay(date: calendar.startOfDay(for: date(start)), stages: [stage])
        }
        show.timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: days)
        context.insert(show)
        return show
    }


    func testOvernightShowTimetableMatchesEndDateAndKeepsLiveState() throws {
        // Oct 15 22:00 -> Oct 16 01:00 (single service day spanning midnight)
        let show = try Show(
            name: "Overnight Club",
            date: date(22),
            startTime: date(22),
            endDate: date(25),
            endTime: date(25),
            timeZoneIdentifier: "Asia/Taipei"
        )
        let p = try TimetablePerformance(artistName: "DJ", startsAt: date(23), endsAt: date(24, 45))
        let stage = try TimetableStage(name: "Club", performances: [p])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = try TimetableDay(date: calendar.startOfDay(for: date(22)), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [day])
        timetable.show = show
        show.timetable = timetable
        context.insert(show)

        XCTAssertTrue(timetable.matchesDates(of: show))
        XCTAssertNotNil(show.lifecycleTimetable)

        let state = CurrentShowTimeState(show: show, now: date(24))
        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.endBoundary, date(25))
    }

    func testRestDayCountdownHelperDoesNotSayTomorrow() throws {
        // Friday 14:00-23:00 (h: 14..23), Sunday 14:00-23:00 (h: 62..71)
        let show = try lifecycleShow(sessions: [(14, 23), (62, 71)], endDay: 48)
        let state = CurrentShowTimeState(show: show, now: date(23, 30))
        XCTAssertEqual(state.kind, .dayEnded)
        XCTAssertEqual(state.nextSessionStartsAt, date(62))
        XCTAssertFalse(state.helperText.contains("明天"))
        XCTAssertTrue(state.helperText.contains("后天") || state.helperText.contains("14:00"))
    }


    func testModifyingPerformanceEndTimeTouchesShowUpdatedAtAndUpdatesPostShowNotification() throws {
        let show = try lifecycleShow(sessions: [(14, 20)])
        let initialUpdated = show.updatedAt
        let performance = try XCTUnwrap(show.timetable?.orderedDays.first?.performances.first)

        // Modify performance endsAt from 20:00 to 23:00
        performance.endsAt = date(23)
        show.updatedAt = Date()
        try context.save()

        XCTAssertTrue(show.updatedAt >= initialUpdated)
        let state = CurrentShowTimeState(show: show, now: date(21))
        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.endBoundary, date(23))

        let scheduler = LocalNotificationScheduler()
        let requests = scheduler.futureRequests(for: show, now: date(10), scope: .all)
        XCTAssertEqual(requests.first { $0.milestone == .postShowRitual }?.fireDate, date(23, 15))
    }

    func testAddingPerformanceToLastDayExtendsShowEndBoundary() throws {
        let show = try lifecycleShow(sessions: [(14, 20)])
        let day = try XCTUnwrap(show.timetable?.orderedDays.first)
        let stage = try XCTUnwrap(day.stages.first)

        let newPerf = try TimetablePerformance(artistName: "Headliner", startsAt: date(21), endsAt: date(23, 30))
        context.insert(newPerf)
        newPerf.stage = stage
        show.updatedAt = Date()
        try context.save()

        let state = CurrentShowTimeState(show: show, now: date(22))
        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.endBoundary, date(23, 30))

        let snapshot = WidgetShowSnapshot(show: show, generatedAt: date(22))
        XCTAssertEqual(CurrentShowTimeState(timing: snapshot.timing, now: date(22)).endBoundary, date(23, 30))
    }


    func testPerformanceRejectsEmptyNameAndInvalidInterval() {
        XCTAssertThrowsError(try TimetablePerformance(artistName: "   ", startsAt: date(14), endsAt: date(15))) { error in
            XCTAssertEqual(error as? TimetableValidationError, .emptyArtistName)
        }
        XCTAssertThrowsError(try TimetablePerformance(artistName: "Valid Artist", startsAt: date(15), endsAt: date(14))) { error in
            XCTAssertEqual(error as? TimetableValidationError, .invalidPerformanceInterval)
        }
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1790956800 + Double(hour) * 3_600 + Double(minute) * 60)
    }
}
