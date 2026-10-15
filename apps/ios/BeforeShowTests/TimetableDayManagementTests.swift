import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableDayManagementTests: XCTestCase {
    func testDateChangesPreserveLocalTimesOvernightSetsAndArtistStateAcrossDST() throws {
        for (zone, month, originalDay, targetDay) in [
            ("Asia/Shanghai", 10, 17, 19),
            ("America/Los_Angeles", 3, 7, 9),
            ("America/Los_Angeles", 10, 31, 29)
        ] {
            let original = date(zone, month, originalDay)
            let target = date(zone, month, targetDay)
            let first = try TimetablePerformance(
                artistName: "First", startsAt: date(zone, month, originalDay, 23, 30),
                endsAt: date(zone, month, originalDay + 1, 1, 15),
                appleMusicArtistID: "123", artistAvatarURL: "https://example.com/artist.jpg"
            )
            first.isInterested = true
            let late = try TimetablePerformance(
                artistName: "Late", startsAt: date(zone, month, originalDay + 1, 1, 30),
                endsAt: date(zone, month, originalDay + 1, 4)
            )
            let stage = try TimetableStage(name: "Main", performances: [first, late])
            let day = try TimetableDay(date: original, stages: [stage])
            let timetable = try Timetable(timeZoneIdentifier: zone, days: [day])
            let originalIDs = [day.id, stage.id, first.id, late.id]

            try timetable.updateDayDate(day, to: target.addingTimeInterval(12 * 3600))

            XCTAssertEqual(day.date, target)
            XCTAssertEqual(first.startsAt, date(zone, month, targetDay, 23, 30))
            XCTAssertEqual(first.endsAt, date(zone, month, targetDay + 1, 1, 15))
            XCTAssertEqual(late.startsAt, date(zone, month, targetDay + 1, 1, 30))
            XCTAssertEqual(late.endsAt, date(zone, month, targetDay + 1, 4))
            XCTAssertEqual([day.id, stage.id, first.id, late.id], originalIDs)
            XCTAssertEqual(first.appleMusicArtistID, "123")
            XCTAssertEqual(first.artistAvatarURL, "https://example.com/artist.jpg")
            XCTAssertTrue(first.isInterested)
            XCTAssertNoThrow(try TimetableDraft(from: timetable).buildTimetable())
        }
    }

    func testDuplicateDatesAndOverlappingDaysAreRejectedBeforeMutation() throws {
        let first = try makeDay(17, startsAt: date("Asia/Shanghai", 10, 17, 23), endsAt: date("Asia/Shanghai", 10, 18, 16))
        let next = try makeDay(19)
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [first, next])
        let original = TimetableDraft(from: timetable)

        XCTAssertThrowsError(try timetable.updateDayDate(first, to: next.date)) {
            XCTAssertEqual($0 as? TimetableValidationError, .invalidDayDate)
        }
        XCTAssertThrowsError(try timetable.addDay(date: first.date.addingTimeInterval(12 * 3600), stageNames: ["Main"])) {
            XCTAssertEqual($0 as? TimetableValidationError, .invalidDayDate)
        }
        XCTAssertThrowsError(try timetable.updateDayDate(first, to: date("Asia/Shanghai", 10, 18))) {
            XCTAssertEqual($0 as? TimetableValidationError, .overlappingDays)
        }
        XCTAssertEqual(TimetableDraft(from: timetable), original)
    }

    func testManagingDaysPersistsChangesAndCascadesOnlyTheDeletedDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("days.store")
        let dayID: UUID
        let performanceID: UUID
        do {
            let container = try diskContainer(url)
            let context = container.mainContext
            let show = try Show(name: "Festival", date: date("Asia/Shanghai", 10, 17), startTime: date("Asia/Shanghai", 10, 17, 14))
            let first = try makeDay(17)
            let selected = try XCTUnwrap(first.performances.first)
            selected.connectArtist(RecognizedArtist(id: "123", canonicalName: "First", avatarURL: nil, appleMusicURL: nil))
            selected.isInterested = true
            dayID = first.id
            performanceID = selected.id
            let timetable = try Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [first])
            show.timetable = timetable
            show.assets = [ShowAsset(showID: show.id, kind: .timetable, relativePath: "original.jpg")]
            context.insert(show)
            try context.save()
            let coordinator = TimetableManagementCoordinator()

            show.name = "Edited Festival"
            XCTAssertNil(coordinator.addDay(date: first.date, to: timetable, template: first, context: context))
            XCTAssertEqual(show.name, "Edited Festival")
            let added = try XCTUnwrap(coordinator.addDay(date: date("Asia/Shanghai", 10, 18), to: timetable, template: first, context: context))
            XCTAssertEqual(added.orderedStages.map(\.name), ["Main"])
            // A new day copies the stage names but invents no sets.
            XCTAssertTrue(added.performances.isEmpty)
            XCTAssertEqual(added.timetable?.id, timetable.id)
            XCTAssertEqual(added.stages.first?.day?.id, added.id)
            // An empty day can still move to another date.
            coordinator.updateDayDate(added, to: date("Asia/Shanghai", 10, 21), in: timetable, context: context)
            XCTAssertNil(coordinator.dayManagementError)
            XCTAssertEqual(added.date, date("Asia/Shanghai", 10, 21))

            coordinator.updateDayDate(first, to: date("Asia/Shanghai", 10, 19), in: timetable, context: context)
            XCTAssertNil(coordinator.dayManagementError)
            XCTAssertTrue(coordinator.deleteDay(added, from: timetable, context: context))
            XCTAssertFalse(coordinator.deleteDay(first, from: timetable, context: context))
        }

        let reloaded = try diskContainer(url)
        let context = reloaded.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let day = try XCTUnwrap(show.timetable?.orderedDays.first)
        let performance = try XCTUnwrap(day.performances.first)
        XCTAssertEqual(show.name, "Edited Festival")
        XCTAssertEqual(day.id, dayID)
        XCTAssertEqual(day.date, date("Asia/Shanghai", 10, 19))
        XCTAssertEqual(performance.id, performanceID)
        XCTAssertEqual(performance.startsAt, date("Asia/Shanghai", 10, 19, 14))
        XCTAssertEqual(performance.appleMusicArtistID, "123")
        XCTAssertTrue(performance.isInterested)
        XCTAssertEqual(show.assets.map(\.relativePath), ["original.jpg"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetableDay>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetableStage>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetablePerformance>()), 1)
    }

    func testStageManagementAddsEmptyStagesReordersAndKeepsAtLeastOne() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let day = try makeDay(17)
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [day])
        context.insert(timetable)
        try context.save()
        let coordinator = TimetableManagementCoordinator()

        XCTAssertTrue(coordinator.addStage(named: "  Love  ", to: day, context: context))
        let love = try XCTUnwrap(day.orderedStages.last)
        XCTAssertEqual(love.name, "Love")
        XCTAssertTrue(love.performances.isEmpty)
        XCTAssertEqual(day.performances.count, 1)
        XCTAssertFalse(coordinator.addStage(named: " ", to: day, context: context))
        XCTAssertEqual(coordinator.dayManagementError, BSLocalization.text("请输入舞台名称"))

        coordinator.reorderStages(of: day, to: [love.id, day.orderedStages[0].id], context: context)
        XCTAssertEqual(day.orderedStages.map(\.name), ["Love", "Main"])

        XCTAssertTrue(coordinator.renameStage(love, to: "Wind", context: context))
        XCTAssertEqual(love.name, "Wind")

        let main = try XCTUnwrap(day.orderedStages.last)
        XCTAssertTrue(coordinator.deleteStage(main, from: day, context: context))
        XCTAssertEqual(day.orderedStages.map(\.name), ["Wind"])
        XCTAssertFalse(coordinator.deleteStage(love, from: day, context: context))
        XCTAssertEqual(day.stages.count, 1)
    }

    private func makeDay(_ day: Int, startsAt: Date? = nil, endsAt: Date? = nil) throws -> TimetableDay {
        try TimetableDay(date: date("Asia/Shanghai", 10, day), stages: [
            TimetableStage(name: "Main", performances: [
                TimetablePerformance(artistName: "First", startsAt: startsAt ?? date("Asia/Shanghai", 10, day, 14), endsAt: endsAt ?? date("Asia/Shanghai", 10, day, 15))
            ])
        ])
    }

    private func date(_ zone: String, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func diskContainer(_ url: URL) throws -> ModelContainer {
        try ModelContainerFactory.make(configuration: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }
}
