import XCTest
@testable import BeforeShow

final class ArtistWarmupPresentationTests: XCTestCase {
    func testFixtureParserReadsRequiredLaunchArgumentValues() {
        let required: [ArtistWarmupDebugFixture.State] = [
            .noCurrentShow,
            .canceledShow,
            .postponedUndated,
            .matchingUnconnected,
            .authorizationDenied,
            .noSubscription,
            .preShowSingle,
            .preShowMulti,
            .catalogLoading,
            .catalogComplete,
            .nowPlaying,
            .postShowRecall
        ]

        for state in required {
            XCTAssertEqual(
                ArtistWarmupDebugFixture.State.parseLaunchArguments([
                    "BeforeShow",
                    "--artist-warmup-fixture",
                    state.rawValue
                ]),
                state
            )
        }
    }

    func testFixtureParserIgnoresMissingAndUnknownValues() {
        XCTAssertNil(ArtistWarmupDebugFixture.State.parseLaunchArguments(["BeforeShow"]))
        XCTAssertNil(ArtistWarmupDebugFixture.State.parseLaunchArguments([
            "BeforeShow",
            "--artist-warmup-fixture"
        ]))
        XCTAssertNil(ArtistWarmupDebugFixture.State.parseLaunchArguments([
            "BeforeShow",
            "--artist-warmup-fixture",
            "blind-guess"
        ]))
    }

    func testFixturePresentationRoutesPageAndCapabilityStatesSeparately() {
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.noCurrentShow).presentation.screen, .noCurrentShow)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.canceledShow).presentation.screen, .unavailable)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.matchingUnconnected).presentation.screen, .candidateConnection)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.authorizationDenied).presentation.screen, .authorizationDenied)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.noSubscription).presentation.screen, .noSubscription)
    }

    func testFixturePresentationRoutesWarmupCatalogPlayerAndRecallStates() {
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.postponedUndated).presentation.screen, .home)
        XCTAssertFalse(ArtistWarmupDebugFixture.make(.postponedUndated).presentation.lifecycle.isOpeningSnapshotEligible)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.preShowSingle).presentation.screen, .home)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.preShowMulti).presentation.screen, .home)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.catalogLoading).presentation.screen, .catalogLoading)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.catalogComplete).presentation.screen, .catalog)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.nowPlaying).presentation.screen, .player)
        XCTAssertEqual(ArtistWarmupDebugFixture.make(.postShowRecall).presentation.screen, .postShowRecall)
    }

    func testMultiArtistPresentationKeepsInterestAndFamiliarityIndependent() throws {
        let presentation = ArtistWarmupDebugFixture.make(.preShowMulti).presentation

        XCTAssertEqual(presentation.artists.count, 3)
        XCTAssertEqual(presentation.artists.map(\.interest), [.wanted, .maybe, .notInterested])
        XCTAssertEqual(presentation.artists.map(\.familiarity.percent), [25, 12, 100])
    }

    func testSavingImpressionDoesNotMutateFamiliarity() throws {
        let presentation = ArtistWarmupDebugFixture.make(.preShowSingle).presentation
        let before = try XCTUnwrap(presentation.artists.first?.familiarity)

        let afterPresentation = presentation.savingImpression(
            songID: "jay-mojito",
            wantsLive: true,
            hasFeeling: true,
            note: "想在灯亮的时候听到"
        )

        XCTAssertEqual(afterPresentation.artists.first?.familiarity, before)
        XCTAssertEqual(afterPresentation.impressions["jay-mojito"]?.note, "想在灯亮的时候听到")
    }

    func testFocusedRoutesHideFloatingTab() {
        XCTAssertFalse(ArtistWarmupPresentationScreen.home.hidesFloatingTab)
        XCTAssertTrue(ArtistWarmupPresentationScreen.catalog.hidesFloatingTab)
        XCTAssertTrue(ArtistWarmupPresentationScreen.catalogLoading.hidesFloatingTab)
        XCTAssertTrue(ArtistWarmupPresentationScreen.player.hidesFloatingTab)
    }

    @MainActor
    func testLivePresentationKeepsArtistMatchSeparateFromDeniedAuthorization() throws {
        let show = try makeUpcomingShow(name: "授权未开的现场", artist: "The Chairs")
        let artist = connectedArtist(showID: show.id, artistID: "artist-1", label: "The Chairs")

        let presentation = ArtistWarmupLivePresentationBuilder.make(
            shows: [show],
            selections: [CurrentShowSelection(selectedShowID: show.id)],
            showArtists: [artist],
            catalogSnapshots: [],
            catalogSongs: [],
            familiarityRecords: [],
            impressions: [],
            recallRecords: [],
            authorizationStatus: .denied,
            subscriptionCapability: ArtistWarmupSubscriptionCapability(
                canPlayCatalogContent: false,
                canBecomeSubscriber: true,
                hasCloudLibraryEnabled: false
            )
        )

        XCTAssertEqual(presentation.screen, .authorizationDenied)
        XCTAssertEqual(presentation.artists.map(\.isConnected), [true])
        XCTAssertEqual(presentation.artists.first?.familiarity.catalogSongCount, 0)
    }

    @MainActor
    func testLivePresentationRoutesNoSubscriptionWithoutDroppingConnectedArtist() throws {
        let show = try makeUpcomingShow(name: "没有订阅的现场", artist: "The Chairs")
        let artist = connectedArtist(showID: show.id, artistID: "artist-1", label: "The Chairs")
        let catalog = ArtistCatalogSnapshot.complete(
            artistID: "artist-1",
            songIDs: ["song-1", "song-2"],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let presentation = ArtistWarmupLivePresentationBuilder.make(
            shows: [show],
            selections: [CurrentShowSelection(selectedShowID: show.id)],
            showArtists: [artist],
            catalogSnapshots: [catalog],
            catalogSongs: [],
            familiarityRecords: [],
            impressions: [],
            recallRecords: [],
            authorizationStatus: .authorized,
            subscriptionCapability: ArtistWarmupSubscriptionCapability(
                canPlayCatalogContent: false,
                canBecomeSubscriber: true,
                hasCloudLibraryEnabled: false
            )
        )

        XCTAssertEqual(presentation.screen, .noSubscription)
        XCTAssertEqual(presentation.artists.map(\.id), ["artist-1"])
        XCTAssertTrue(presentation.artists[0].isConnected)
        XCTAssertEqual(presentation.artists[0].familiarity.catalogSongCount, 2)
    }

    @MainActor
    func testLivePresentationHidesFamiliarityDenominatorUntilCatalogIsComplete() throws {
        let show = try makeUpcomingShow(name: "曲库还在整理的现场", artist: "The Chairs")
        let artist = connectedArtist(showID: show.id, artistID: "artist-1", label: "The Chairs")
        let loading = ArtistCatalogSnapshot.loading(artistID: "artist-1")

        let presentation = ArtistWarmupLivePresentationBuilder.make(
            shows: [show],
            selections: [CurrentShowSelection(selectedShowID: show.id)],
            showArtists: [artist],
            catalogSnapshots: [loading],
            catalogSongs: [],
            familiarityRecords: [SongFamiliarityRecord(songID: "song-1", heardAt: Date(), source: .manual)],
            impressions: [],
            recallRecords: [],
            authorizationStatus: .authorized,
            subscriptionCapability: playableCapability
        )

        XCTAssertEqual(presentation.screen, .home)
        XCTAssertEqual(presentation.artists.first?.familiarity.catalogSongCount, 0)
        XCTAssertEqual(presentation.artists.first?.familiarity.heardSongCount, 0)
        XCTAssertFalse(presentation.artists.first?.familiarity.hasCompleteCatalog ?? true)
    }

    @MainActor
    func testLivePresentationTreatsAllNotInterestedAsEmptyQueue() throws {
        let show = try makeUpcomingShow(name: "都不看的现场", artist: "A, B")
        let first = connectedArtist(showID: show.id, artistID: "artist-a", label: "A", interest: .notInterested)
        let second = connectedArtist(showID: show.id, artistID: "artist-b", label: "B", interest: .notInterested)

        let presentation = ArtistWarmupLivePresentationBuilder.make(
            shows: [show],
            selections: [CurrentShowSelection(selectedShowID: show.id)],
            showArtists: [first, second],
            catalogSnapshots: [],
            catalogSongs: [],
            familiarityRecords: [],
            impressions: [],
            recallRecords: [],
            authorizationStatus: .authorized,
            subscriptionCapability: playableCapability
        )

        XCTAssertEqual(presentation.screen, .home)
        XCTAssertTrue(presentation.hasEmptyWarmupQueue)
    }

    func testCatalogPresentationGroupsAlbumSingleAndCollaborationSongs() {
        let songs = [
            CatalogSong(
                appleMusicSongID: "album-1",
                title: "Album Song",
                performingArtistIDs: ["artist-1"],
                performingArtistNames: ["Artist"],
                category: .album
            ),
            CatalogSong(
                appleMusicSongID: "single-1",
                title: "Single Song",
                performingArtistIDs: ["artist-1"],
                performingArtistNames: ["Artist"],
                category: .single
            ),
            CatalogSong(
                appleMusicSongID: "collab-1",
                title: "Collab Song",
                performingArtistIDs: ["artist-1", "artist-2"],
                performingArtistNames: ["Artist", "Guest"],
                category: .collaboration
            )
        ]

        let grouped = CatalogSongPresentationGrouping.group(songs)
        XCTAssertEqual(grouped[.albums]?.map(\.appleMusicSongID), ["album-1"])
        XCTAssertEqual(grouped[.singles]?.map(\.appleMusicSongID), ["single-1"])
        XCTAssertEqual(grouped[.collaborations]?.map(\.appleMusicSongID), ["collab-1"])
    }

    private var playableCapability: ArtistWarmupSubscriptionCapability {
        ArtistWarmupSubscriptionCapability(
            canPlayCatalogContent: true,
            canBecomeSubscriber: false,
            hasCloudLibraryEnabled: true
        )
    }

    private func connectedArtist(
        showID: UUID,
        artistID: String,
        label: String,
        interest: ArtistInterest = .wanted
    ) -> ShowArtist {
        let artist = ShowArtist(
            showID: showID,
            originalArtistLabel: label,
            originalOrder: 0,
            interest: interest
        )
        artist.confirmAppleMusicArtist(id: artistID, name: label, artworkURL: nil)
        return artist
    }

    private func makeUpcomingShow(name: String, artist: String) throws -> Show {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 10,
            day: 1,
            hour: 0
        ).date!
        let startTime = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 10,
            day: 1,
            hour: 20
        ).date!
        return try Show(name: name, date: date, startTime: startTime, artist: artist)
    }
}
