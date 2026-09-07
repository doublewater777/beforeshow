import XCTest
import SwiftData
@testable import BeforeShow

@MainActor enum ListenTestData {
    static func make(ended: Bool = false) throws -> (ModelContainer, Show) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(ended ? -10000 : 10000)
        let show = try Show(name: "Test Show", date: start, startTime: start)
        if ended { show.endedAt = start.addingTimeInterval(100) }
        show.artists = [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a"),
                        ArtistSlot(name: "B", avatarURL: nil), ArtistSlot(name: "C", avatarURL: nil, appleMusicArtistID: "c")]
        context.insert(show)
        for id in ["a1", "a2", "c1"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: String(id.prefix(1)), duration: 100))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "a", artistName: "A", orderedSongIDs: ["a1", "a2"], topSongIDs: ["a2"], albumIDs: ["album"]))
        context.insert(ArtistCatalogSnapshot(artistID: "c", artistName: "C", orderedSongIDs: ["c1"]))
        context.insert(CatalogAlbum(appleMusicAlbumID: "album", title: "Album", artistIDs: ["a"], orderedTrackIDs: ["a2", "a1"]))
        try context.save()
        return (container, show)
    }
    static func room(_ context: ModelContext) -> ListeningRoomCoordinator {
        ListeningRoomCoordinator(context: context, catalogService: ListenTestCatalog(), artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { _ in ListeningFixturePlayer() })
    }
    static func settle(_ room: ListeningRoomCoordinator, until condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            let m = room.mechanism.motion
            m.lid.step(1); m.discX.step(1); m.discY.step(1); m.lift.step(1); m.discScale.step(1)
            room.mechanism.refresh()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Physical operation did not settle")
    }
}
private struct ListenTestCatalog: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { .init(authorizationStatus: .authorized, canPlayCatalogContent: true) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload { throw ListeningCatalogError.artistNotFound(artistID) }
}

final class NavigationTests: XCTestCase {
    func testThreeTabsOrder() { XCTAssertEqual(BeforeShowTab.allCases, [.current, .listen, .footprints]) }
}
final class ListeningPresentationTests: XCTestCase {
    func testCacheAlwaysRemainsBrowsable() {
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: true, loading: false, failed: false), .ready)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: true, loading: false, failed: true), .cachedWithError)
    }
    func testUnavailableStates() {
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: false, loading: true, failed: false, accessResolved: false), .loading)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: false, authorized: false, connected: false, hasSongs: false, loading: false, failed: false), .noCurrentShow)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: false, loading: false, failed: false), .needsAuthorization)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: false, hasSongs: false, loading: false, failed: false), .noConnectedArtists)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: false, loading: true, failed: false), .loadingCatalog)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: false, loading: false, failed: true), .fatalUnavailable)
    }
    @MainActor func testEveryFixtureIsIsolatedAndReproducible() throws {
        for scenario in ListeningFixtureScenario.allCases {
            let fixture = try ListeningDebugFixtures(scenario: scenario)
            let count = try fixture.container.mainContext.fetchCount(FetchDescriptor<Show>())
            XCTAssertEqual(count, scenario == .noCurrent ? 0 : 1)
        }
    }
}
final class ListeningAccessibilityTests: XCTestCase {
    func testUserPauseNeverResumesFromLifecycle() {
        var policy = ListeningVisibilityPolicy()
        policy.interrupt(wasPlaying: true)
        XCTAssertTrue(policy.resumeIfAllowed())
        policy.userPause(); policy.interrupt(wasPlaying: true)
        XCTAssertFalse(policy.resumeIfAllowed())
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .fullCatalog))
        XCTAssertTrue(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .preview))
        XCTAssertTrue(ListeningVisibilityPolicy.mustPause(tabVisible: false, foreground: true, source: .fullCatalog))
    }
    func testAccessibleActionsAndReducedMotionRemainWired() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow/Features/Listening")
        let card = try String(contentsOf: root.appendingPathComponent("Views/ListeningSongCardView.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains(#"accessibilityAction(named: BSLocalization.text("下一曲")"#))
        XCTAssertTrue(card.contains(#"accessibilityAction(named: BSLocalization.text("上一曲")"#))
        XCTAssertTrue(card.contains(#"accessibilityIdentifier("listening.nowPlaying")"#))
        XCTAssertTrue(card.contains(#"accessibilityIdentifier("listening.discTracks")"#))
        XCTAssertEqual(card.components(separatedBy: "onShowTracks?()").count - 1, 1)
        let room = try String(contentsOf: root.appendingPathComponent("Views/ListeningRoomView.swift"), encoding: .utf8)
        XCTAssertTrue(room.contains("accessibilityReduceMotion"))
        XCTAssertTrue(room.contains("motion.reducedMotion = value"))
        XCTAssertTrue(room.contains(".font(BSFont.pageTitle)"))
        XCTAssertFalse(room.contains(#"Text(BSLocalization.text("听"))"#))
        XCTAssertTrue(room.contains("Text(show.name)"))
        XCTAssertTrue(room.contains(".accessibilityAddTraits(.isHeader)"))
        let sheet = try String(contentsOf: root.appendingPathComponent("Views/ListeningCabinetSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("ListeningShelf {"))
        XCTAssertFalse(sheet.contains("JewelCaseShelf"))
    }
}

@MainActor final class ListeningWantsLivePresentationTests: XCTestCase {
    func testFrozenAndCanceledAreReadOnlyAndShowScoped() throws {
        let (container, show) = try ListenTestData.make()
        let repo = ListeningRepository(modelContext: container.mainContext)
        try repo.setWantsLive(showID: show.id, songID: "a1", isWanted: true)
        XCTAssertTrue(WantsLivePolicy.isMutable(show: show))
        XCTAssertFalse(WantsLivePolicy.isMutable(show: show, now: Date().addingTimeInterval(20000)))
        XCTAssertThrowsError(try repo.setWantsLive(showID: show.id, songID: "a1", isWanted: false, at: Date().addingTimeInterval(20000)))
        show.changeStatus = .canceled
        XCTAssertFalse(WantsLivePolicy.isMutable(show: show))
        XCTAssertThrowsError(try repo.setWantsLive(showID: show.id, songID: "a2", isWanted: true))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
        let frozen = ListeningWantsLivePresentation(selected: true, mutable: false)
        XCTAssertEqual(frozen.label, "开场前想现场听")
        XCTAssertEqual(frozen.symbol, "heart.fill")
    }
}
@MainActor final class ListeningArtistMatchingTests: XCTestCase {
    func testCandidateDoesNotWriteUntilConfirmation() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let candidate = RecognizedArtist(id: "new", canonicalName: "New Artist", avatarURL: nil, appleMusicURL: URL(string: "https://music.apple.com/artist/123"))
        XCTAssertNil(show.artists[1].appleMusicArtistID)
        await room.rematch(slotIndex: 1, artist: candidate)
        XCTAssertEqual(show.artists[1].appleMusicArtistID, "new")
        XCTAssertEqual(show.artists[1].name, "New Artist")
        XCTAssertEqual(show.artists[1].appleMusicURL, candidate.appleMusicURL?.absoluteString)
    }
}
@MainActor final class ListeningArtistPreferenceTests: XCTestCase {
    func testScopeIsRuntimeAndExclusionReturnsToWholeShow() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.filterArtist("a")
        XCTAssertEqual(room.onlyArtistID, "a")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        room.excludeArtist("a", excluded: true)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertEqual(room.excludedArtistIDs, ["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        XCTAssertTrue(rows.allSatisfy { $0.showID == show.id })
        room.excludeArtist("a", excluded: false)
        XCTAssertTrue(room.excludedArtistIDs.isEmpty)
    }
}
@MainActor final class ListeningArtistLibraryTests: XCTestCase {
    func testTopAndAlbumOrderUseCatalogAndUnconnectedDoesNotBlock() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertEqual(room.discs.first?.tracks.map(\.id), ["a1", "c1", "a2"])
        let artist = try XCTUnwrap(room.artistPresentation("a"))
        XCTAssertEqual(artist.top.map(\.id), ["a2"])
        XCTAssertEqual(artist.albums.first?.tracks.map(\.id), ["a2", "a1"])
        XCTAssertTrue(try XCTUnwrap(room.artistPresentation("c")).top.isEmpty)
        room.playLibrarySong(artist.all[1], artistID: "a")
        try await ListenTestData.settle(room) { room.isPlaying && room.track?.id == "a2" }
        XCTAssertEqual(room.mechanism.disc?.id, "album")
        room.setActive(false)
    }
}
@MainActor final class ListeningArtistRematchTests: XCTestCase {
    func testRematchKeepsBaselineAndGlobalEvidence() async throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let repo = ListeningRepository(modelContext: context)
        try repo.confirmManualFamiliarity(songID: "a1", at: Date().addingTimeInterval(-20000))
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
        try repo.setArtistExcluded(showID: show.id, artistID: "a", isExcluded: true)
        try context.save()
        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        let captured = baseline.capturedAt
        let room = ListenTestData.room(context)
        await room.load(show: show)
        await room.rematch(slotIndex: 0, artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil))
        XCTAssertEqual(baseline.capturedAt, captured)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>()).contains { $0.artistID == "a" })
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).contains { $0.artistID == "a" })
    }
}
