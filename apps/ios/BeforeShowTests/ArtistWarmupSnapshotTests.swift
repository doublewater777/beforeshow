import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistWarmupSnapshotTests: XCTestCase {
    func testOpeningCaptureCreatesOneImmutableSnapshotForConnectedArtistWithCompleteCatalog() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = makeCalendar()
        let show = try makeShow(
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, calendar: calendar)
        )
        let artist = connectedArtist(showID: show.id, artistID: "artist-1")
        let catalog = ArtistCatalogSnapshot.complete(
            artistID: "artist-1",
            songIDs: ["song-1", "song-2", "song-3", "song-3"],
            fetchedAt: makeDate(year: 2026, month: 7, day: 7, hour: 12, calendar: calendar)
        )
        context.insert(show)
        context.insert(artist)
        context.insert(catalog)
        context.insert(SongFamiliarityRecord(songID: "song-1", heardAt: Date(timeIntervalSince1970: 100), source: .manual))
        try context.save()

        let service = ArtistWarmupSnapshotService(context: context)
        let openedAt = makeDate(year: 2026, month: 7, day: 8, hour: 20, calendar: calendar)
        let snapshots = try service.captureOpeningSnapshots(for: show, now: openedAt, calendar: calendar)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].showID, show.id)
        XCTAssertEqual(snapshots[0].artistID, "artist-1")
        XCTAssertEqual(snapshots[0].heardSongCount, 1)
        XCTAssertEqual(snapshots[0].totalSongCount, 3)
        XCTAssertEqual(snapshots[0].tier, .investedFan)
        XCTAssertEqual(snapshots[0].capturedAt, openedAt)

        context.insert(SongFamiliarityRecord(songID: "song-2", heardAt: Date(timeIntervalSince1970: 200), source: .manual))
        let secondPass = try service.captureOpeningSnapshots(
            for: show,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 21, calendar: calendar),
            calendar: calendar
        )
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(secondPass.count, 1)
        XCTAssertEqual(stored[0].heardSongCount, 1)
        XCTAssertEqual(stored[0].capturedAt, openedAt)
    }

    func testOpeningCaptureSkipsIneligibleShowsAndIncompleteCatalogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = makeCalendar()
        let opening = makeDate(year: 2026, month: 7, day: 8, hour: 20, calendar: calendar)
        let service = ArtistWarmupSnapshotService(context: context)

        let canceled = try eligibleShow(calendar: calendar)
        canceled.markCanceled()
        try insertWarmupFixtures(show: canceled, artistID: "canceled-artist", catalog: .complete(["song-1"]), context: context)

        let undatedPostponed = try eligibleShow(calendar: calendar)
        undatedPostponed.markPostponed(newDate: nil)
        try insertWarmupFixtures(show: undatedPostponed, artistID: "undated-artist", catalog: .complete(["song-2"]), context: context)

        let unconnected = try eligibleShow(calendar: calendar)
        context.insert(unconnected)
        context.insert(ShowArtist(showID: unconnected.id, originalArtistLabel: "Unmatched", originalOrder: 0, interest: .wanted))
        context.insert(ArtistCatalogSnapshot.complete(artistID: "missing-link", songIDs: ["song-3"], fetchedAt: opening))

        let partial = try eligibleShow(calendar: calendar)
        try insertWarmupFixtures(show: partial, artistID: "partial-artist", catalog: .loading, context: context)

        let failed = try eligibleShow(calendar: calendar)
        try insertWarmupFixtures(show: failed, artistID: "failed-artist", catalog: .failed, context: context)

        let empty = try eligibleShow(calendar: calendar)
        try insertWarmupFixtures(show: empty, artistID: "empty-artist", catalog: .complete([]), context: context)

        try context.save()

        for show in [canceled, undatedPostponed, unconnected, partial, failed, empty] {
            XCTAssertTrue(try service.captureOpeningSnapshots(for: show, now: opening, calendar: calendar).isEmpty)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).isEmpty)
    }

    func testDatedPostponedShowCapturesWhenPostponedOpeningHasArrived() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = makeCalendar()
        let originalDay = makeDate(year: 2026, month: 7, day: 8, hour: 0, calendar: calendar)
        let originalStart = makeDate(year: 2026, month: 7, day: 8, hour: 20, calendar: calendar)
        let postponedDay = makeDate(year: 2026, month: 7, day: 10, hour: 0, calendar: calendar)
        let show = try makeShow(date: originalDay, startTime: originalStart)
        show.markPostponed(newDate: postponedDay)
        try insertWarmupFixtures(show: show, artistID: "artist-1", catalog: .complete(["song-1"]), context: context)
        try context.save()

        let service = ArtistWarmupSnapshotService(context: context)

        XCTAssertTrue(
            try service.captureOpeningSnapshots(
                for: show,
                now: makeDate(year: 2026, month: 7, day: 10, hour: 19, calendar: calendar),
                calendar: calendar
            ).isEmpty
        )
        XCTAssertEqual(
            try service.captureOpeningSnapshots(
                for: show,
                now: makeDate(year: 2026, month: 7, day: 10, hour: 20, calendar: calendar),
                calendar: calendar
            ).count,
            1
        )
    }

    func testCatalogRecallUpsertsShowMemoryAndGlobalFamiliarityWithoutChangingSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        let snapshot = ShowArtistFamiliaritySnapshot.capture(
            showID: showID,
            artistID: "artist-1",
            heardSongCount: 0,
            totalSongCount: 2,
            tier: .firstListen,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(snapshot)
        try context.save()

        let service = ArtistWarmupSnapshotService(context: context)
        _ = try service.confirmCatalogSongHeardAtShow(
            showID: showID,
            songID: "song-1",
            heardAtShow: Date(timeIntervalSince1970: 200),
            now: Date(timeIntervalSince1970: 201)
        )
        _ = try service.confirmCatalogSongHeardAtShow(
            showID: showID,
            songID: "song-1",
            heardAtShow: Date(timeIntervalSince1970: 300),
            now: Date(timeIntervalSince1970: 301)
        )
        try context.save()

        let memories = try context.fetch(FetchDescriptor<ShowSetlistMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].catalogSongID, "song-1")
        XCTAssertEqual(memories[0].heardAtShow, Date(timeIntervalSince1970: 300))

        let familiarity = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(familiarity.count, 1)
        XCTAssertEqual(familiarity[0].songID, "song-1")
        XCTAssertEqual(familiarity[0].heardAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(familiarity[0].source, .showRecall)

        let snapshots = try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].heardSongCount, 0)
        XCTAssertEqual(snapshots[0].capturedAt, Date(timeIntervalSince1970: 100))
    }

    func testManualRecallStoresShowMemoryWithoutCatalogSongOrFamiliarity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        let service = ArtistWarmupSnapshotService(context: context)

        let memory = try service.rememberManualSongAtShow(
            showID: showID,
            title: "Unreleased Cover Medley",
            artistName: "Guest Singer",
            heardAtShow: Date(timeIntervalSince1970: 400),
            isMostSurprising: true,
            now: Date(timeIntervalSince1970: 401)
        )
        try context.save()

        XCTAssertNil(memory.catalogSongID)
        XCTAssertEqual(memory.manualTitle, "Unreleased Cover Medley")
        XCTAssertEqual(memory.manualArtistName, "Guest Singer")
        XCTAssertTrue(memory.isMostSurprising)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).isEmpty)
    }

    func testOnlyOneMostSurprisingMemoryPerShow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = ArtistWarmupSnapshotService(context: context)
        let showID = UUID()
        let otherShowID = UUID()

        _ = try service.confirmCatalogSongHeardAtShow(
            showID: showID,
            songID: "song-1",
            heardAtShow: Date(timeIntervalSince1970: 100),
            isMostSurprising: true,
            now: Date(timeIntervalSince1970: 101)
        )
        _ = try service.rememberManualSongAtShow(
            showID: showID,
            title: "New Song",
            artistName: nil,
            heardAtShow: Date(timeIntervalSince1970: 200),
            isMostSurprising: true,
            now: Date(timeIntervalSince1970: 201)
        )
        _ = try service.confirmCatalogSongHeardAtShow(
            showID: otherShowID,
            songID: "song-2",
            heardAtShow: Date(timeIntervalSince1970: 300),
            isMostSurprising: true,
            now: Date(timeIntervalSince1970: 301)
        )
        try context.save()

        let memories = try context.fetch(FetchDescriptor<ShowSetlistMemory>())
        let targetShowMemories = memories.filter { $0.showID == showID }
        XCTAssertEqual(targetShowMemories.filter(\.isMostSurprising).count, 1)
        XCTAssertEqual(targetShowMemories.first { $0.isMostSurprising }?.manualTitle, "New Song")
        XCTAssertEqual(memories.filter { $0.showID == otherShowID && $0.isMostSurprising }.count, 1)
    }

    func testDeleteShowLocalWarmupRecordsPreservesGlobalFamiliarity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        context.insert(connectedArtist(showID: showID, artistID: "artist-1"))
        context.insert(ShowSongImpression(showID: showID, songID: "song-1", wantsLive: true, hasFeeling: true, note: nil))
        context.insert(ShowArtistFamiliaritySnapshot.capture(showID: showID, artistID: "artist-1", heardSongCount: 1, totalSongCount: 2, tier: .familiarFan))
        context.insert(ShowSetlistMemory(showID: showID, catalogSongID: "song-1", manualTitle: nil, manualArtistName: nil, heardAtShow: Date(timeIntervalSince1970: 100)))
        context.insert(SongFamiliarityRecord(songID: "song-1", heardAt: Date(timeIntervalSince1970: 100), source: .showRecall))
        try context.save()

        let service = ArtistWarmupSnapshotService(context: context)
        try service.deleteShowLocalWarmupRecords(for: showID)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowArtist>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowSongImpression>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowSetlistMemory>()).isEmpty)

        let familiarity = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(familiarity.count, 1)
        XCTAssertEqual(familiarity[0].songID, "song-1")
        XCTAssertEqual(familiarity[0].source, .showRecall)
    }

    private enum CatalogFixture {
        case loading
        case failed
        case complete([String])
    }

    private func insertWarmupFixtures(
        show: Show,
        artistID: String,
        catalog: CatalogFixture,
        context: ModelContext
    ) throws {
        context.insert(show)
        context.insert(connectedArtist(showID: show.id, artistID: artistID))
        switch catalog {
        case .loading:
            context.insert(ArtistCatalogSnapshot.loading(artistID: artistID))
        case .failed:
            context.insert(ArtistCatalogSnapshot.failed(artistID: artistID, fetchedAt: Date(timeIntervalSince1970: 100)))
        case let .complete(songIDs):
            context.insert(ArtistCatalogSnapshot.complete(artistID: artistID, songIDs: songIDs, fetchedAt: Date(timeIntervalSince1970: 100)))
        }
    }

    private func connectedArtist(showID: UUID, artistID: String) -> ShowArtist {
        let artist = ShowArtist(
            showID: showID,
            originalArtistLabel: "Artist \(artistID)",
            originalOrder: 0,
            interest: .wanted
        )
        artist.confirmAppleMusicArtist(id: artistID, name: "Artist \(artistID)", artworkURL: nil)
        return artist
    }

    private func eligibleShow(calendar: Calendar) throws -> Show {
        try makeShow(
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, calendar: calendar)
        )
    }

    private func makeShow(date: Date, startTime: Date) throws -> Show {
        try Show(name: "Warmup Live", date: date, startTime: startTime)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            ShowArtist.self,
            ArtistCatalogSnapshot.self,
            CatalogSong.self,
            SongFamiliarityRecord.self,
            ShowSongImpression.self,
            ShowArtistFamiliaritySnapshot.self,
            ShowSetlistMemory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
