import XCTest
@testable import BeforeShow

final class ArtistWarmupDomainTests: XCTestCase {
    func testInterestLabelsMatchChineseCopy() {
        XCTAssertEqual(ArtistInterest.wanted.label, "想看")
        XCTAssertEqual(ArtistInterest.maybe.label, "待定")
        XCTAssertEqual(ArtistInterest.notInterested.label, "不看")
    }

    func testFamiliarityRequiresCompleteNonEmptyCatalog() {
        XCTAssertNil(
            ArtistFamiliarity.summary(
                catalogEnumeration: .partial(songIDs: ["a"]),
                heardSongIDs: ["a"]
            )
        )
        XCTAssertNil(
            ArtistFamiliarity.summary(
                catalogEnumeration: .complete(songIDs: []),
                heardSongIDs: ["a"]
            )
        )
    }

    func testFamiliarityUsesUniqueHeardSongsInsideCatalog() {
        let summary = ArtistFamiliarity.summary(
            catalogEnumeration: .complete(songIDs: ["a", "b", "c", "c"]),
            heardSongIDs: ["a", "a", "outside"]
        )

        XCTAssertEqual(summary?.heardSongCount, 1)
        XCTAssertEqual(summary?.catalogSongCount, 3)
        XCTAssertEqual(summary?.percent, 33)
        XCTAssertEqual(summary?.tierLabel, "入坑乐迷")
    }

    func testFamiliarityTierLabelsCoverBoundaryPercentages() {
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 0), "初见听众")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 1), "新晋听众")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 24), "新晋听众")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 25), "入坑乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 49), "入坑乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 50), "熟悉乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 74), "熟悉乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 75), "深度乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 99), "深度乐迷")
        XCTAssertEqual(ArtistFamiliarityTier.label(forPercent: 100), "全曲库知己")
    }

    func testNewCatalogSongsCanLowerFamiliarityPercent() {
        let original = ArtistFamiliarity.summary(
            catalogEnumeration: .complete(songIDs: ["a", "b"]),
            heardSongIDs: ["a"]
        )
        let expanded = ArtistFamiliarity.summary(
            catalogEnumeration: .complete(songIDs: ["a", "b", "c", "d"]),
            heardSongIDs: ["a"]
        )

        XCTAssertEqual(original?.percent, 50)
        XCTAssertEqual(expanded?.percent, 25)
    }

    func testImpressionLedgerIsSeparateFromFamiliarity() {
        let impressions = ArtistWarmupImpressionLedger(impressedSongIDs: ["a", "b", "b"])
        let summary = ArtistFamiliarity.summary(
            catalogEnumeration: .complete(songIDs: ["a", "b"]),
            heardSongIDs: []
        )

        XCTAssertEqual(impressions.uniqueImpressedSongCount, 2)
        XCTAssertEqual(summary?.heardSongCount, 0)
        XCTAssertEqual(summary?.percent, 0)
        XCTAssertEqual(summary?.tierLabel, "初见听众")
    }

    func testLifecycleRoutesNoShowSetupWarmupRecallAndUnavailableStates() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, calendar: calendar)
        let tomorrow = makeDate(year: 2026, month: 6, day: 16, hour: 20, calendar: calendar)
        let yesterday = makeDate(year: 2026, month: 6, day: 14, hour: 22, calendar: calendar)

        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(show: nil, music: .connected, artistMatch: .matched, now: now, calendar: calendar).route,
            .noCurrentShow
        )
        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(
                show: .scheduled(startsAt: tomorrow),
                music: .unconnected,
                artistMatch: .matched,
                now: now,
                calendar: calendar
            ).route,
            .matchingOrUnconnected
        )
        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(
                show: .scheduled(startsAt: tomorrow),
                music: .connected,
                artistMatch: .matching,
                now: now,
                calendar: calendar
            ).route,
            .matchingOrUnconnected
        )
        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(
                show: .scheduled(startsAt: tomorrow),
                music: .connected,
                artistMatch: .matched,
                now: now,
                calendar: calendar
            ).route,
            .warmup
        )
        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(
                show: .scheduled(startsAt: yesterday),
                music: .connected,
                artistMatch: .matched,
                now: now,
                calendar: calendar
            ).route,
            .postShowRecall
        )
        XCTAssertEqual(
            ArtistWarmupLifecycle.resolve(
                show: .canceled,
                music: .connected,
                artistMatch: .matched,
                now: now,
                calendar: calendar
            ).route,
            .unavailable
        )
    }

    func testLifecycleRecallExpiresAfterThreeDays() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, calendar: calendar)
        let outsideRetention = makeDate(year: 2026, month: 6, day: 11, hour: 11, calendar: calendar)

        let state = ArtistWarmupLifecycle.resolve(
            show: .scheduled(startsAt: outsideRetention),
            music: .connected,
            artistMatch: .matched,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.route, .noCurrentShow)
    }

    func testUndatedPostponedStaysWarmupButCannotOpenSnapshotOrDateReminder() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, calendar: calendar)

        let state = ArtistWarmupLifecycle.resolve(
            show: .undatedPostponed,
            music: .connected,
            artistMatch: .matched,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.route, .warmup)
        XCTAssertFalse(state.isOpeningSnapshotEligible)
        XCTAssertFalse(state.isDateReminderEligible)
    }

    func testQueueBuilderExcludesNotInterestedIncludesMaybeAndPrioritizesWanted() {
        let queue = ArtistWarmupQueueBuilder.build(
            from: [
                ArtistWarmupTrack(id: "maybe-1", artistID: "a", interest: .maybe),
                ArtistWarmupTrack(id: "skip", artistID: "a", interest: .notInterested),
                ArtistWarmupTrack(id: "wanted-1", artistID: "a", interest: .wanted),
                ArtistWarmupTrack(id: "wanted-2", artistID: "b", interest: .wanted),
                ArtistWarmupTrack(id: "maybe-2", artistID: "a", interest: .maybe)
            ],
            scope: .allArtists
        )

        XCTAssertEqual(queue.map(\.id), ["wanted-1", "wanted-2", "maybe-1", "maybe-2"])
    }

    func testQueueBuilderSupportsArtistOnlyScopeAndEmptyAllExcludedResult() {
        let scoped = ArtistWarmupQueueBuilder.build(
            from: [
                ArtistWarmupTrack(id: "a-wanted", artistID: "a", interest: .wanted),
                ArtistWarmupTrack(id: "b-wanted", artistID: "b", interest: .wanted),
                ArtistWarmupTrack(id: "a-maybe", artistID: "a", interest: .maybe)
            ],
            scope: .artistOnly("a")
        )
        let empty = ArtistWarmupQueueBuilder.build(
            from: [
                ArtistWarmupTrack(id: "skip-1", artistID: "a", interest: .notInterested),
                ArtistWarmupTrack(id: "skip-2", artistID: "b", interest: .notInterested)
            ],
            scope: .allArtists
        )

        XCTAssertEqual(scoped.map(\.id), ["a-wanted", "a-maybe"])
        XCTAssertTrue(empty.isEmpty)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date {
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
