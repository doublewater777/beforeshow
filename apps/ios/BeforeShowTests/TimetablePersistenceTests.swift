import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetablePersistenceTests: XCTestCase {
    func testSingleAndMultiDayGraphsSurviveDiskReloadWithIndependentInterestAndSourceImage() throws {
        for dayCount in [1, 2] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("timetable.store")
            var performanceID: UUID!
            var showID: UUID!
            do {
                let container = try diskContainer(at: url)
                let context = container.mainContext
                let show = try makeShow()
                let timetable = try makeTimetable(dayCount: dayCount)
                show.timetable = timetable
                let selected = try XCTUnwrap(timetable.orderedDays.first?.orderedStages.first?.orderedPerformances.first)
                selected.isInterested = true
                performanceID = selected.id
                showID = show.id
                let source = ShowAsset(showID: show.id, kind: .timetable, relativePath: "original.jpg")
                show.assets = [source]
                context.insert(show)
                try context.save()
            }
            do {
                let container = try diskContainer(at: url)
                let context = container.mainContext
                let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
                let timetable = try XCTUnwrap(show.timetable)
                XCTAssertEqual(show.id, showID)
                XCTAssertEqual(timetable.show?.id, showID)
                XCTAssertEqual(timetable.timeZoneIdentifier, "Asia/Taipei")
                XCTAssertEqual(timetable.orderedDays.map(\.date), (0..<dayCount).map { date($0 * 24) })
                let all = timetable.orderedDays.flatMap(\.performances)
                XCTAssertEqual(all.count, dayCount * 3)
                XCTAssertEqual(all.filter(\.isInterested).map(\.id), [performanceID!])
                for day in timetable.orderedDays {
                    XCTAssertEqual(day.timetable?.id, timetable.id)
                    XCTAssertEqual(day.orderedStages.map(\.name), ["Main", "River"])
                    XCTAssertEqual(day.orderedStages[0].orderedPerformances.map(\.artistName), ["Same Artist", "Late Artist"])
                    for stage in day.stages {
                        XCTAssertEqual(stage.day?.id, day.id)
                        XCTAssertTrue(stage.performances.allSatisfy { $0.stage?.id == stage.id })
                    }
                }
                let midnight = TimetableTimePolicy.facts(for: timetable.timing, at: date(24))
                XCTAssertEqual(midnight.current.map(\.id), [timetable.orderedDays[0].orderedStages[0].orderedPerformances[1].id])
                XCTAssertFalse(midnight.hasEnded)
                XCTAssertEqual(show.assets.map(\.relativePath), ["original.jpg"])
                XCTAssertEqual(show.assets.first?.kind, .timetable)
                XCTAssertNil(show.endedAt)
                XCTAssertTrue(show.memoryFragments.isEmpty)

                let selected = try XCTUnwrap(all.first { $0.id == performanceID })
                selected.isInterested = false
                try context.save()
            }
            let reloaded = try diskContainer(at: url)
            XCTAssertFalse(try reloaded.mainContext.fetch(FetchDescriptor<TimetablePerformance>()).contains { $0.isInterested })
        }
    }

    func testDeletingTimetableKeepsSourceAndShowWhileDeletingShowCascadesEntireGraph() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try makeShow()
        show.timetable = try makeTimetable(dayCount: 2)
        show.assets = [ShowAsset(showID: show.id, kind: .timetable, relativePath: "original.jpg")]
        context.insert(show)
        try context.save()

        context.delete(try XCTUnwrap(show.timetable))
        try context.save()
        let reloaded = ModelContext(container)
        let retainedShow = try XCTUnwrap(reloaded.fetch(FetchDescriptor<Show>()).first)
        XCTAssertNil(retainedShow.timetable)
        XCTAssertEqual(retainedShow.assets.map(\.relativePath), ["original.jpg"])
        try assertNoTimetableRecords(in: reloaded)

        retainedShow.timetable = try makeTimetable(dayCount: 2)
        try reloaded.save()
        XCTAssertEqual(try reloaded.fetchCount(FetchDescriptor<TimetablePerformance>()), 6)
        reloaded.delete(retainedShow)
        try reloaded.save()
        let afterDelete = ModelContext(container)
        try assertNoTimetableRecords(in: afterDelete)
        XCTAssertEqual(try afterDelete.fetchCount(FetchDescriptor<Show>()), 0)
        XCTAssertEqual(try afterDelete.fetchCount(FetchDescriptor<ShowAsset>()), 0)
    }

    func testBulkShowDeletionReclaimsTimetableRecords() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try makeShow()
        show.timetable = try makeTimetable(dayCount: 2)
        context.insert(show)
        try context.save()

        // Settings clears all local data through this bulk-delete API.
        try context.delete(model: Show.self)
        try context.save()
        try assertNoTimetableRecords(in: ModelContext(container))
    }

    func testInvalidRecognitionDataCannotCreateStructuredTimetable() throws {
        for end in [date(10), date(9)] {
            XCTAssertThrowsError(try TimetablePerformance(artistName: "Artist", startsAt: date(10), endsAt: end)) {
                XCTAssertEqual($0 as? TimetableValidationError, .invalidPerformanceInterval)
            }
        }
        XCTAssertThrowsError(try TimetablePerformance(artistName: " \n", startsAt: date(10), endsAt: date(11))) {
            XCTAssertEqual($0 as? TimetableValidationError, .emptyArtistName)
        }
        XCTAssertThrowsError(try Timetable(timeZoneIdentifier: "Invalid/Zone", days: [])) {
            XCTAssertEqual($0 as? TimetableValidationError, .invalidTimeZone)
        }
        XCTAssertThrowsError(try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [])) {
            XCTAssertEqual($0 as? TimetableValidationError, .emptyTimetable)
        }
        let mismatchedDay = try makeDay(dayOffset: 0, officialDate: date(24))
        XCTAssertThrowsError(try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [mismatchedDay])) {
            XCTAssertEqual($0 as? TimetableValidationError, .invalidDayDate)
        }
        let duplicateDate = try [makeDay(dayOffset: 0), makeDay(dayOffset: 0)]
        XCTAssertThrowsError(try Timetable(timeZoneIdentifier: "Asia/Taipei", days: duplicateDate)) {
            XCTAssertEqual($0 as? TimetableValidationError, .invalidDayDate)
        }
        let firstDay = try makeDay(dayOffset: 0)
        let overlapping = try TimetableDay(date: date(24), stages: [
            TimetableStage(name: "Main", performances: [
                TimetablePerformance(artistName: "Artist", startsAt: date(24), endsAt: date(26))
            ])
        ])
        XCTAssertThrowsError(try Timetable(timeZoneIdentifier: "Asia/Taipei", days: [firstDay, overlapping])) {
            XCTAssertEqual($0 as? TimetableValidationError, .overlappingDays)
        }
    }

    private func diskContainer(at url: URL) throws -> ModelContainer {
        let appContainer = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        return try ModelContainer(for: appContainer.schema, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }

    private func makeShow() throws -> Show {
        try Show(name: "Festival", date: date(0), startTime: date(20), timeZoneIdentifier: "Asia/Taipei")
    }

    private func makeTimetable(dayCount: Int) throws -> Timetable {
        try Timetable(timeZoneIdentifier: "Asia/Taipei", days: (0..<dayCount).reversed().map { try makeDay(dayOffset: $0) })
    }

    private func makeDay(dayOffset: Int, officialDate: Date? = nil) throws -> TimetableDay {
        let offset = dayOffset * 24
        let late = try TimetablePerformance(artistName: "Late Artist", startsAt: date(offset + 23), endsAt: date(offset + 25))
        let first = try TimetablePerformance(artistName: "Same Artist", startsAt: date(offset + 20), endsAt: date(offset + 21))
        let parallel = try TimetablePerformance(artistName: "Same Artist", startsAt: date(offset + 20), endsAt: date(offset + 22))
        let main = try TimetableStage(name: "Main", sortOrder: 0, performances: [late, first])
        let river = try TimetableStage(name: "River", sortOrder: 1, performances: [parallel])
        return try TimetableDay(date: officialDate ?? date(offset), stages: [river, main])
    }

    private func assertNoTimetableRecords(in context: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Timetable>()), 0, file: file, line: line)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetableDay>()), 0, file: file, line: line)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetableStage>()), 0, file: file, line: line)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimetablePerformance>()), 0, file: file, line: line)
    }

    private func date(_ hour: Int) -> Date {
        // 2026-10-03 00:00 Asia/Taipei, independent of the simulator's time zone.
        Date(timeIntervalSince1970: 1790956800 + Double(hour) * 3_600)
    }
}
