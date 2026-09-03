import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class OpeningFamiliarityCoordinatorTests: XCTestCase {
    func testCaptureDueBaselinesCoversAllEligibleShowsWithoutArtistOrCatalog() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let dueWithoutArtist = try Show(
            name: "Due no artist",
            date: now.addingTimeInterval(-600),
            startTime: now.addingTimeInterval(-600)
        )
        let dueWithoutCatalog = try Show(
            name: "Due no catalog",
            date: now.addingTimeInterval(-1_200),
            startTime: now.addingTimeInterval(-1_200),
            artists: [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "artist-a")]
        )
        let future = try Show(
            name: "Future",
            date: now.addingTimeInterval(600),
            startTime: now.addingTimeInterval(600)
        )
        let historical = try Show(
            name: "Historical",
            date: now.addingTimeInterval(-10_000),
            startTime: now.addingTimeInterval(-10_000),
            wasAddedAsHistorical: true
        )
        let canceled = try Show(
            name: "Canceled",
            date: now.addingTimeInterval(-10_000),
            startTime: now.addingTimeInterval(-10_000),
            changeStatus: .canceled
        )
        let postponed = try Show(
            name: "Postponed",
            date: now.addingTimeInterval(-10_000),
            startTime: now.addingTimeInterval(-10_000)
        )
        postponed.changeStatus = .postponed
        postponed.postponedDate = nil

        [dueWithoutArtist, dueWithoutCatalog, future, historical, canceled, postponed].forEach(context.insert)
        context.insert(SongFamiliarityRecord(
            songID: "known-song",
            manualConfirmedAt: now.addingTimeInterval(-20_000)
        ))
        try context.save()

        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context, now: now)

        let baselines = try context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
        XCTAssertEqual(Set(baselines.map(\.showID)), Set([dueWithoutArtist.id, dueWithoutCatalog.id]))
        XCTAssertTrue(baselines.allSatisfy { $0.familiarSongIDsAtCapture == ["known-song"] })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
    }

    func testLateCatalogUsesFrozenBaselineAndIgnoresPostOpeningFamiliarity() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "Late catalog",
            date: now.addingTimeInterval(-60),
            startTime: now.addingTimeInterval(-60),
            artists: [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        )
        context.insert(show)
        context.insert(SongFamiliarityRecord(
            songID: "song-1",
            manualConfirmedAt: now.addingTimeInterval(-300)
        ))
        try context.save()

        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context, now: now)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context, now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)

        let repository = ListeningRepository(modelContext: context)
        _ = try repository.confirmManualFamiliarity(
            songID: "song-2",
            at: now.addingTimeInterval(1)
        )
        _ = try repository.upsertArtistCatalogSnapshot(
            artistID: "artist",
            artistName: "Artist",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: ["song-1", "song-2", "song-3", "song-4"],
            topSongIDs: [],
            albumIDs: [],
            fetchedAt: now.addingTimeInterval(2)
        )
        try context.save()

        try OpeningFamiliarityCoordinator.resolveAvailableTiers(
            in: context,
            now: now.addingTimeInterval(3)
        )

        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        XCTAssertEqual(baseline.familiarSongIDsAtCapture, ["song-1"])
        let tier = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).first)
        XCTAssertEqual(tier.tierRawValue, ListeningFamiliarityTier.gettingIntoIt.rawValue)

        _ = try repository.confirmManualFamiliarity(
            songID: "song-3",
            at: now.addingTimeInterval(4)
        )
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(
            in: context,
            now: now.addingTimeInterval(5)
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).first?.tierRawValue,
            ListeningFamiliarityTier.gettingIntoIt.rawValue,
            "opening tier is immutable after resolution"
        )
    }

    func testLifecycleDeletesBaselineAndTierWhenShowMovesBackIntoFuture() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "Rescheduled",
            date: now.addingTimeInterval(-3_600),
            startTime: now.addingTimeInterval(-3_600),
            artists: [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a")]
        )
        context.insert(show)
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: show.id,
            effectiveStartAtCapture: now.addingTimeInterval(-3_600),
            familiarSongIDsAtCapture: ["song"],
            capturedAt: now.addingTimeInterval(-3_000)
        ))
        context.insert(ShowOpeningArtistTier(
            showID: show.id,
            artistID: "a",
            artistNameAtCapture: "A",
            tierRawValue: ListeningFamiliarityTier.deepListener.rawValue,
            baselineCapturedAt: now.addingTimeInterval(-3_000),
            catalogSnapshotFetchedAt: now.addingTimeInterval(-4_000)
        ))
        try context.save()

        let future = now.addingTimeInterval(86_400)
        show.date = future
        show.startTime = future
        _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context, now: now)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
    }

    func testPastStartCorrectionKeepsExistingBaselineImmutable() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let originalStart = now.addingTimeInterval(-3_600)
        let show = try Show(name: "Past correction", date: originalStart, startTime: originalStart)
        let baseline = ShowOpeningFamiliarityBaseline(
            showID: show.id,
            effectiveStartAtCapture: originalStart,
            familiarSongIDsAtCapture: ["song"],
            capturedAt: now.addingTimeInterval(-3_000)
        )
        context.insert(show)
        context.insert(baseline)
        try context.save()

        let correctedPast = now.addingTimeInterval(-1_800)
        show.date = correctedPast
        show.startTime = correctedPast
        _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context, now: now)
        try context.save()

        let retained = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        XCTAssertEqual(retained.effectiveStartAtCapture, originalStart)
        XCTAssertEqual(retained.familiarSongIDsAtCapture, ["song"])
    }

    func testCanceledAndUndatedPostponedShowsInvalidateOpeningState() throws {
        for status in [ShowChangeStatus.canceled, .postponed] {
            let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
            let context = container.mainContext
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let start = now.addingTimeInterval(-3_600)
            let show = try Show(
                name: "Invalidated",
                date: start,
                startTime: start,
                artists: [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a")]
            )
            context.insert(show)
            context.insert(ShowOpeningFamiliarityBaseline(
                showID: show.id,
                effectiveStartAtCapture: start,
                familiarSongIDsAtCapture: []
            ))
            context.insert(ShowOpeningArtistTier(
                showID: show.id,
                artistID: "a",
                artistNameAtCapture: "A",
                tierRawValue: ListeningFamiliarityTier.firstEncounter.rawValue,
                baselineCapturedAt: now,
                catalogSnapshotFetchedAt: now
            ))
            try context.save()

            show.changeStatus = status
            if status == .postponed { show.postponedDate = nil }
            _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context, now: now)
            try context.save()

            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        }
    }

    func testArtistRematchKeepsBaselineButDropsOldScopedStateAndResolvesNewTier() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = now.addingTimeInterval(-3_600)
        let show = try Show(
            name: "Rematch",
            date: start,
            startTime: start,
            artists: [ArtistSlot(name: "Old", avatarURL: nil, appleMusicArtistID: "old")]
        )
        let baseline = ShowOpeningFamiliarityBaseline(
            showID: show.id,
            effectiveStartAtCapture: start,
            familiarSongIDsAtCapture: ["song-1"],
            capturedAt: now.addingTimeInterval(-3_000)
        )
        context.insert(show)
        context.insert(baseline)
        context.insert(ShowOpeningArtistTier(
            showID: show.id,
            artistID: "old",
            artistNameAtCapture: "Old",
            tierRawValue: ListeningFamiliarityTier.firstEncounter.rawValue,
            baselineCapturedAt: baseline.capturedAt,
            catalogSnapshotFetchedAt: now.addingTimeInterval(-10_000)
        ))
        context.insert(ShowArtistListeningPreference(
            showID: show.id,
            artistID: "old",
            isExcluded: true
        ))
        context.insert(ArtistCatalogSnapshot(
            artistID: "new",
            artistName: "New",
            orderedSongIDs: ["song-1", "song-2"],
            fetchedAt: now
        ))
        try context.save()

        show.artists = [ArtistSlot(name: "New", avatarURL: nil, appleMusicArtistID: "new")]
        _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context, now: now)
        _ = try OpeningFamiliarityCoordinator.resolveAvailableTiers(
            in: context,
            now: now,
            saveChanges: false
        )
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        let tiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>())
        XCTAssertEqual(tiers.count, 1)
        XCTAssertEqual(tiers.first?.artistID, "new")
        XCTAssertEqual(tiers.first?.tierRawValue, ListeningFamiliarityTier.familiar.rawValue)
    }
}
