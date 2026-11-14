import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningLineupScheduleTests: XCTestCase {
    func testShowDayPinsThatDayAndKeepsTheRestByDate() {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let day3 = midnight(calendar, 2026, 4, 13)
        let performances = [
            slot("A", day1, calendar, 10, 0, index: 0),
            slot("B", day1, calendar, 12, 0, index: 1),
            slot("C", day2, calendar, 11, 0, index: 2),
            slot("A", day2, calendar, 18, 0, index: 3),
            slot("D", day3, calendar, 9, 0, index: 4),
        ]
        let today = ListeningLineupSchedule.ordered(
            lineup: ["Z", "A", "B", "C", "D"],
            performances: performances,
            now: time(calendar, 2026, 4, 12, 9, 0),
            calendar: calendar
        )
        XCTAssertEqual(today.map(\.name), ["C", "A", "B", "D", "Z"])
        XCTAssertEqual(today.first { $0.name == "A" }?.performance?.start, time(calendar, 2026, 4, 12, 18, 0))

        let before = ListeningLineupSchedule.ordered(
            lineup: ["Z", "A", "B", "C", "D"],
            performances: performances,
            now: time(calendar, 2026, 4, 10, 22, 0),
            calendar: calendar
        )
        XCTAssertEqual(before.map(\.name), ["A", "B", "C", "D", "Z"])
        XCTAssertEqual(before.first { $0.name == "A" }?.performance?.start, time(calendar, 2026, 4, 11, 10, 0))

        let after = ListeningLineupSchedule.ordered(
            lineup: ["Z", "A", "B", "C", "D"],
            performances: performances,
            now: time(calendar, 2026, 4, 14, 1, 0),
            calendar: calendar
        )
        XCTAssertEqual(after.map(\.name), ["A", "B", "C", "D", "Z"])
    }

    func testBeforeTheFestivalDoesNotKeepLineupOrderOverStartTime() {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["B", "A", "C", "Z"],
            performances: [
                slot("A", day1, calendar, 18, 0, index: 0),
                slot("B", day1, calendar, 22, 0, index: 1),
                slot("C", day2, calendar, 10, 0, index: 2),
            ],
            now: time(calendar, 2026, 4, 10, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.name), ["A", "B", "C", "Z"])
    }

    func testNoTimetableKeepsTheLineup() {
        let ordered = ListeningLineupSchedule.ordered(
            lineup: [" Z ", "A", "A", "B", ""],
            performances: [],
            now: Date(timeIntervalSince1970: 0),
            calendar: calendar("America/Los_Angeles")
        )
        XCTAssertEqual(ordered.map(\.name), ["Z", "A", "B"])
        XCTAssertTrue(ordered.allSatisfy { $0.performance == nil })
    }

    func testShowTimeZoneTodayWinsWhenUTCIsAlreadyTheNextDay() {
        let losAngeles = calendar("America/Los_Angeles")
        let utc = calendar("UTC")
        let april11 = midnight(losAngeles, 2026, 4, 11)
        let april12 = midnight(losAngeles, 2026, 4, 12)
        let now = time(losAngeles, 2026, 4, 11, 20, 0)
        XCTAssertTrue(losAngeles.isDate(now, inSameDayAs: april11))
        XCTAssertFalse(losAngeles.isDate(now, inSameDayAs: april12))
        XCTAssertTrue(utc.isDate(now, inSameDayAs: april12))
        XCTAssertFalse(utc.isDate(now, inSameDayAs: april11))
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["Late", "Early"],
            performances: [
                slot("Early", april11, losAngeles, 10, 0, index: 0),
                slot("Late", april12, losAngeles, 10, 0, index: 1),
            ],
            now: now,
            calendar: losAngeles
        )
        XCTAssertEqual(ordered.map(\.name), ["Early", "Late"])
    }

    func testSameArtistAppearsOnceAndTodayReplacesTheEarlierSet() {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["A", "B"],
            performances: [
                slot("A", day1, calendar, 21, 0, index: 0),
                slot("A", day1, calendar, 22, 0, index: 1),
                slot("B", day2, calendar, 11, 0, index: 2),
                slot("A", day2, calendar, 18, 0, index: 3),
            ],
            now: time(calendar, 2026, 4, 12, 9, 0),
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.name), ["B", "A"])
        XCTAssertEqual(ordered.first { $0.name == "A" }?.performance?.start, time(calendar, 2026, 4, 12, 18, 0))
    }

    func testEqualStartsStayInLineupOrderAndTimetableOnlyNamesFollow() {
        let calendar = calendar("America/Los_Angeles")
        let day = midnight(calendar, 2026, 4, 11)
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["C", "A", "B"],
            performances: [
                slot("D", day, calendar, 20, 0, index: 0),
                slot("B", day, calendar, 20, 0, index: 1),
                slot("A", day, calendar, 20, 0, index: 2),
                slot("C", day, calendar, 20, 0, index: 3),
            ],
            now: time(calendar, 2026, 4, 11, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.name), ["C", "A", "B", "D"])
    }

    func testArtistsWithoutASetStayLastInLineupOrder() {
        let calendar = calendar("America/Los_Angeles")
        let day = midnight(calendar, 2026, 4, 11)
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["M", "A", "N"],
            performances: [slot("A", day, calendar, 15, 0, index: 0)],
            now: time(calendar, 2026, 4, 9, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.name), ["A", "M", "N"])
    }

    func testTodayPinsTheLaterDayAheadOfAnEarlierStart() {
        let calendar = calendar("America/Los_Angeles")
        let ordered = ListeningLineupSchedule.ordered(
            lineup: ["A", "B"],
            performances: [
                slot("A", midnight(calendar, 2026, 4, 11), calendar, 10, 0, index: 0),
                slot("B", midnight(calendar, 2026, 4, 12), calendar, 20, 0, index: 1),
            ],
            now: time(calendar, 2026, 4, 12, 8, 0),
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.name), ["B", "A"])
    }

    func testPinTodayKeepsRelativeOrderInsideAndOutsideTheDay() {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let programs: [(program: ListeningCompilationAssembler.LiveProgram, day: Date)] = [
            (ListeningCompilationAssembler.LiveProgram(key: "stage-1", title: "s1", sets: []), day1),
            (ListeningCompilationAssembler.LiveProgram(key: "wanted-2", title: "w2", sets: []), day2),
            (ListeningCompilationAssembler.LiveProgram(key: "stage-2", title: "s2", sets: []), day2),
            (ListeningCompilationAssembler.LiveProgram(key: "wanted-1", title: "w1", sets: []), day1),
        ]
        let pinned = ListeningLineupSchedule.pinToday(programs, now: time(calendar, 2026, 4, 12, 8, 0), calendar: calendar)
        XCTAssertEqual(pinned.map(\.key), ["wanted-2", "stage-2", "stage-1", "wanted-1"])
        let outside = ListeningLineupSchedule.pinToday(programs, now: time(calendar, 2026, 4, 10, 8, 0), calendar: calendar)
        XCTAssertEqual(outside.map(\.key), ["stage-1", "wanted-2", "stage-2", "wanted-1"])
    }

    func testWatchChipUsesTheSetThatSortedTheArtist() throws {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let show = try Show(name: "Watch", date: day1, startTime: day1, timeZoneIdentifier: "America/Los_Angeles")
        show.artists = [ArtistSlot(name: "A", avatarURL: nil), ArtistSlot(name: "B", avatarURL: nil)]
        let early = try TimetablePerformance(artistName: "A", startsAt: time(calendar, 2026, 4, 11, 21, 0), endsAt: time(calendar, 2026, 4, 11, 22, 0))
        let later = try TimetablePerformance(artistName: "A", startsAt: time(calendar, 2026, 4, 12, 18, 0), endsAt: time(calendar, 2026, 4, 12, 19, 0))
        let opening = try TimetablePerformance(artistName: "B", startsAt: time(calendar, 2026, 4, 12, 11, 0), endsAt: time(calendar, 2026, 4, 12, 12, 0))
        let first = try TimetableDay(date: day1, stages: [try TimetableStage(name: "Night", performances: [early])])
        let second = try TimetableDay(date: day2, stages: [try TimetableStage(name: "Day", performances: [opening, later])])
        let timetable = try Timetable(timeZoneIdentifier: "America/Los_Angeles", days: [first, second])
        timetable.show = show
        show.timetable = timetable
        container.mainContext.insert(show)
        container.mainContext.insert(timetable)
        let lineup = ListeningVideoLineup(ListeningShowInputs(show), now: time(calendar, 2026, 4, 12, 9, 0), calendar: show.timingCalendar())
        XCTAssertEqual(lineup.artists.map(\.name), ["B", "A"])
        XCTAssertEqual(lineup.artists.first { $0.name == "A" }?.set?.start, time(calendar, 2026, 4, 12, 18, 0))
        XCTAssertEqual(lineup.artists.first { $0.name == "A" }?.stageName, "Day")
        XCTAssertEqual(lineup.artists.map(\.name).filter { $0 == "A" }.count, 1)
    }

    func testCompilationGroupsArtistsInScheduleOrderAndKeepsEachArtistsSongs() throws {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let show = try Show(name: "Playlist", date: day1, startTime: day1, timeZoneIdentifier: "America/Los_Angeles")
        show.artists = ["A", "B", "C"].map { ArtistSlot(name: $0, avatarURL: nil, appleMusicArtistID: $0.lowercased()) }
        let a = try TimetablePerformance(artistName: "A", startsAt: time(calendar, 2026, 4, 11, 21, 0), endsAt: time(calendar, 2026, 4, 11, 22, 0), appleMusicArtistID: "a")
        let b = try TimetablePerformance(artistName: "B", startsAt: time(calendar, 2026, 4, 12, 18, 0), endsAt: time(calendar, 2026, 4, 12, 19, 0), appleMusicArtistID: "b")
        let c = try TimetablePerformance(artistName: "C", startsAt: time(calendar, 2026, 4, 12, 20, 0), endsAt: time(calendar, 2026, 4, 12, 21, 0), appleMusicArtistID: "c")
        show.timetable = try Timetable(timeZoneIdentifier: "America/Los_Angeles", days: [
            try TimetableDay(date: day1, stages: [try TimetableStage(name: "Main", performances: [a])]),
            try TimetableDay(date: day2, stages: [try TimetableStage(name: "Main", performances: [b, c])]),
        ])
        container.mainContext.insert(show)
        let songs = [
            "a": tracks(["a1", "a2", "a3"], artist: "A"),
            "b": tracks(["b1", "b2"], artist: "B"),
            "c": tracks(["c1", "c2", "c3"], artist: "C"),
        ]
        let browse = [
            browse("c", name: "C", slot: 2),
            browse("a", name: "A", slot: 0),
            browse("b", name: "B", slot: 1),
        ]
        let grouped = ListeningShowPlaylistOrdering.artistTracks(
            show: show, browseArtists: browse, topTracks: { songs[$0] ?? [] }, now: time(calendar, 2026, 4, 12, 9, 0)
        )
        let ids = ListeningCompilationAssembler.discs(showID: show.id, artistTracks: grouped).flatMap(\.tracks).map(\.id)
        XCTAssertEqual(ids, ["b1", "b2", "c1", "c2", "c3", "a1", "a2", "a3"])
    }

    func testLiveProgramsOnTheShowDayMoveAheadWithoutReorderingSongs() throws {
        let zone = "America/Los_Angeles"
        let calendar = calendar(zone)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let show = try festival(calendar: calendar, zone: zone, days: [
            (yesterday, "A", "a", ["a1", "a2"]),
            (today, "B", "b", ["b1", "b2"]),
        ])
        let discs = try programs(show)
        XCTAssertEqual(discs.map(\.id), [
            "compilation-\(show.show.id)-wanted-\(show.days[1].id)",
            "compilation-\(show.show.id)-stage-\(show.stages[1].id)",
            "compilation-\(show.show.id)-wanted-\(show.days[0].id)",
            "compilation-\(show.show.id)-stage-\(show.stages[0].id)",
            "compilation-\(show.show.id)-singalong",
        ])
        XCTAssertEqual(discs.map { $0.tracks.map(\.id) }, [
            ["b1", "b2"], ["b1", "b2"], ["a1", "a2"], ["a1", "a2"], ["b1", "b2", "a1", "a2"],
        ])
    }

    func testLiveProgramsOutsideTheFestivalStayInBuiltOrder() throws {
        let zone = "America/Los_Angeles"
        let calendar = calendar(zone)
        let first = calendar.date(byAdding: .day, value: 400, to: calendar.startOfDay(for: Date()))!
        let second = calendar.date(byAdding: .day, value: 1, to: first)!
        let show = try festival(calendar: calendar, zone: zone, days: [
            (first, "A", "a", ["a1", "a2"]),
            (second, "B", "b", ["b1", "b2"]),
        ])
        let discs = try programs(show)
        XCTAssertEqual(discs.map(\.id), [
            "compilation-\(show.show.id)-wanted-\(show.days[0].id)",
            "compilation-\(show.show.id)-wanted-\(show.days[1].id)",
            "compilation-\(show.show.id)-stage-\(show.stages[0].id)",
            "compilation-\(show.show.id)-stage-\(show.stages[1].id)",
            "compilation-\(show.show.id)-singalong",
        ])
        XCTAssertEqual(discs.last?.tracks.map(\.id), ["a1", "a2", "b1", "b2"])
    }

    func testSameRoomReprojectsAcrossShowLocalDaysWithoutResettingTheQueue() throws {
        let calendar = calendar("America/Los_Angeles")
        let day1 = midnight(calendar, 2026, 4, 11)
        let day2 = midnight(calendar, 2026, 4, 12)
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(name: "Across days", date: day1, startTime: day1, timeZoneIdentifier: "America/Los_Angeles")
        show.artists = [
            ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a"),
            ArtistSlot(name: "B", avatarURL: nil, appleMusicArtistID: "b"),
        ]
        for (id, artist) in [("a1", "A"), ("a2", "A"), ("b1", "B"), ("b2", "B")] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: artist, duration: 100))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "a", artistName: "A", orderedSongIDs: ["a1", "a2"], topSongIDs: ["a1", "a2"]))
        context.insert(ArtistCatalogSnapshot(artistID: "b", artistName: "B", orderedSongIDs: ["b1", "b2"], topSongIDs: ["b1", "b2"]))
        let early = try TimetablePerformance(artistName: "A", startsAt: time(calendar, 2026, 4, 11, 21, 0), endsAt: time(calendar, 2026, 4, 11, 22, 0), appleMusicArtistID: "a")
        let later = try TimetablePerformance(artistName: "B", startsAt: time(calendar, 2026, 4, 12, 18, 0), endsAt: time(calendar, 2026, 4, 12, 19, 0), appleMusicArtistID: "b")
        early.isInterested = true
        later.isInterested = true
        let firstDay = try TimetableDay(date: day1, stages: [try TimetableStage(name: "Main", performances: [early])])
        let secondDay = try TimetableDay(date: day2, stages: [try TimetableStage(name: "Main", performances: [later])])
        show.timetable = try Timetable(timeZoneIdentifier: "America/Los_Angeles", days: [firstDay, secondDay])
        context.insert(show)
        try context.save()
        let inputs = ListeningShowInputs(show)
        let room = ListenTestData.room(context)
        defer { room.stop(); room.widgetSync.cancel() }
        room.prepareForDisplay(show: show)

        let morning = time(calendar, 2026, 4, 11, 9, 0)
        room.refreshWidgetForDay(now: morning)
        let dayOneIDs = [
            "compilation-\(show.id)-wanted-\(firstDay.id)",
            "compilation-\(show.id)-stage-\(firstDay.stages[0].id)",
            "compilation-\(show.id)-wanted-\(secondDay.id)",
            "compilation-\(show.id)-stage-\(secondDay.stages[0].id)",
            "compilation-\(show.id)-singalong",
        ]
        XCTAssertEqual(room.compilationDiscs.map(\.id), dayOneIDs)
        XCTAssertEqual(singalongIDs(room), ["a1", "a2", "b1", "b2"])
        XCTAssertEqual(ListeningVideoLineup(inputs, now: room.lineupNow, calendar: show.timingCalendar()).artists.map(\.name), ["A", "B"])

        let stillDayOne = time(calendar, 2026, 4, 11, 23, 30)
        room.refreshWidgetForDay(now: stillDayOne)
        XCTAssertEqual(room.compilationDiscs.map(\.id), dayOneIDs)
        XCTAssertEqual(singalongIDs(room), ["a1", "a2", "b1", "b2"])

        let singalong = try XCTUnwrap(room.compilationDiscs.first { $0.id.hasSuffix("singalong") })
        room.loadDisc(singalong, songID: singalong.tracks.first?.id)
        let queue = room.deck.tracks.map(\.id)
        let cursor = room.deck.cursorSongID
        let seated = room.loadedDisc?.id
        XCTAssertEqual(queue, ["a1", "a2", "b1", "b2"])
        XCTAssertEqual(cursor, "a1")

        let dayTwo = time(calendar, 2026, 4, 12, 8, 0)
        room.refreshWidgetForDay(now: dayTwo)
        XCTAssertEqual(inputs, ListeningShowInputs(show))
        XCTAssertEqual(room.lineupNow, dayTwo)
        XCTAssertEqual(room.compilationDiscs.map(\.id), [
            "compilation-\(show.id)-wanted-\(secondDay.id)",
            "compilation-\(show.id)-stage-\(secondDay.stages[0].id)",
            "compilation-\(show.id)-wanted-\(firstDay.id)",
            "compilation-\(show.id)-stage-\(firstDay.stages[0].id)",
            "compilation-\(show.id)-singalong",
        ])
        XCTAssertEqual(singalongIDs(room), ["b1", "b2", "a1", "a2"])
        XCTAssertEqual(ListeningVideoLineup(inputs, now: room.lineupNow, calendar: show.timingCalendar()).artists.map(\.name), ["B", "A"])
        XCTAssertEqual(room.deck.tracks.map(\.id), queue)
        XCTAssertEqual(room.deck.cursorSongID, cursor)
        XCTAssertEqual(room.loadedDisc?.id, seated)
        XCTAssertEqual(room.loadedDisc?.tracks.map(\.id), queue)

        room.refreshWidgetForDay(now: time(calendar, 2026, 4, 14, 1, 0))
        XCTAssertEqual(room.compilationDiscs.map(\.id), [
            "compilation-\(show.id)-wanted-\(firstDay.id)",
            "compilation-\(show.id)-wanted-\(secondDay.id)",
            "compilation-\(show.id)-stage-\(firstDay.stages[0].id)",
            "compilation-\(show.id)-stage-\(secondDay.stages[0].id)",
            "compilation-\(show.id)-singalong",
        ])
        XCTAssertEqual(singalongIDs(room), ["a1", "a2", "b1", "b2"])
        XCTAssertEqual(room.deck.tracks.map(\.id), queue)
        XCTAssertEqual(room.deck.cursorSongID, cursor)
    }

    private func singalongIDs(_ room: ListeningRoomCoordinator) -> [String] {
        room.compilationDiscs.first { $0.id.hasSuffix("singalong") }?.tracks.map(\.id) ?? []
    }

    private struct Festival {
        var container: ModelContainer
        var show: Show
        var days: [TimetableDay]
        var stages: [TimetableStage]
        var songs: [String: [ListeningDiscTrack]]
    }

    private func programs(_ festival: Festival) throws -> [ListeningDisc] {
        let live = ListeningCompilationAssembler.livePrograms(for: festival.show) { festival.songs[$0] ?? [] }
        let artists = festival.show.artists.enumerated().map { index, slot in
            browse(slot.appleMusicArtistID ?? "", name: slot.name, slot: index)
        }
        let grouped = ListeningShowPlaylistOrdering.artistTracks(
            show: festival.show, browseArtists: artists, topTracks: { festival.songs[$0] ?? [] }
        )
        return ListeningCompilationAssembler.discs(showID: festival.show.id, livePrograms: live, artistTracks: grouped)
    }

    private func festival(
        calendar: Calendar,
        zone: String,
        days: [(Date, String, String, [String])]
    ) throws -> Festival {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let show = try Show(name: "Live", date: days[0].0, startTime: days[0].0, timeZoneIdentifier: zone)
        show.artists = days.map { ArtistSlot(name: $0.1, avatarURL: nil, appleMusicArtistID: $0.2) }
        var timetableDays: [TimetableDay] = []
        var stages: [TimetableStage] = []
        var songs: [String: [ListeningDiscTrack]] = [:]
        for day in days {
            let start = calendar.date(byAdding: .hour, value: 10, to: day.0)!
            let end = calendar.date(byAdding: .hour, value: 11, to: day.0)!
            let performance = try TimetablePerformance(
                artistName: day.1, startsAt: start, endsAt: end, appleMusicArtistID: day.2
            )
            performance.isInterested = true
            let stage = try TimetableStage(name: "Main", performances: [performance])
            stages.append(stage)
            timetableDays.append(try TimetableDay(date: day.0, stages: [stage]))
            songs[day.2] = tracks(day.3, artist: day.1)
        }
        let timetable = try Timetable(timeZoneIdentifier: zone, days: timetableDays)
        timetable.show = show
        show.timetable = timetable
        container.mainContext.insert(show)
        container.mainContext.insert(timetable)
        return Festival(container: container, show: show, days: timetableDays, stages: stages, songs: songs)
    }

    private func slot(
        _ name: String, _ day: Date, _ calendar: Calendar, _ hour: Int, _ minute: Int, index: Int
    ) -> ListeningLineupSchedule.Performance {
        ListeningLineupSchedule.Performance(
            name: name, day: day, start: time(calendar, day, hour, minute), timetableIndex: index
        )
    }

    private func tracks(_ ids: [String], artist: String) -> [ListeningDiscTrack] {
        ids.map { ListeningDiscTrack(id: $0, title: $0, artistName: artist, duration: 100) }
    }

    private func browse(_ id: String, name: String, slot: Int) -> ListeningBrowseArtist {
        ListeningBrowseArtist(slotIndex: slot, id: id, name: name, artworkURL: nil, appleMusicArtistID: id, albums: [])
    }

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func midnight(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
        time(calendar, year, month, day, 0, 0)
    }

    private func time(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    private func time(_ calendar: Calendar, _ day: Date, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }
}
