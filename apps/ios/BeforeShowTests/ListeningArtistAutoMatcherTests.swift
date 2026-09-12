import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningArtistAutoMatcherTests: XCTestCase {
    func testMatchesNamesWithoutOverwritingExistingIdentity() async throws {
        let search = AutoMatchSearchStub(candidates: [candidate("new", "  THE Band ")])
        let slots = [ArtistSlot(name: "the band", avatarURL: nil),
                     ArtistSlot(name: "the band", avatarURL: nil, appleMusicArtistID: "existing")]
        let result = try await ListeningArtistAutoMatcher(search: search).matches(for: slots)
        XCTAssertEqual(result[0]?.id, "new")
        XCTAssertNil(result[1])
        let queries = await search.queries
        XCTAssertEqual(queries, ["the band"])
    }

    func testUsesExistingAppleMusicLinkWithoutSearch() async throws {
        let search = AutoMatchSearchStub(candidates: [])
        let slot = ArtistSlot(name: "Artist", avatarURL: nil, appleMusicURL: "https://music.apple.com/cn/artist/artist/12345")
        let result = try await ListeningArtistAutoMatcher(search: search).matches(for: [slot])
        XCTAssertEqual(result[0]?.id, "12345")
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testAmbiguousAndUnrelatedSearchResultsDoNotAttachWrongArtist() async throws {
        let slots = [ArtistSlot(name: "Artist", avatarURL: nil)]
        let ambiguous = AutoMatchSearchStub(candidates: [candidate("one", "Artist"), candidate("two", "Artist")])
        let unrelated = AutoMatchSearchStub(candidates: [candidate("other", "Different Artist")])
        let first = try await ListeningArtistAutoMatcher(search: ambiguous).matches(for: slots)
        let second = try await ListeningArtistAutoMatcher(search: unrelated).matches(for: slots)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
    }

    func testInternalWhitespaceDifferenceDoesNotAutoMatch() async throws {
        let search = AutoMatchSearchStub(candidates: [candidate("wrong", "AB")])
        let result = try await ListeningArtistAutoMatcher(search: search).matches(for: [ArtistSlot(name: "A B", avatarURL: nil)])
        XCTAssertTrue(result.isEmpty)
    }

    func testArtistSearchPrefersMusicKitCatalogForLongTailChineseArtist() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { query, _ in
                [RecognizedArtist(
                    id: "1766242527",
                    canonicalName: query,
                    avatarURL: nil,
                    appleMusicURL: URL(string: "https://music.apple.com/cn/artist/1766242527")
                )]
            },
            fallbackSearch: { _, _ in
                throw ArtistSearchPolicyTestError.unexpectedFallback
            }
        )

        let results = try await service.searchArtists(query: "姜思达")
        XCTAssertEqual(results.map(\.id), ["1766242527"])
        XCTAssertEqual(results.map(\.canonicalName), ["姜思达"])
    }

    func testArtistSearchFallsBackWhenCatalogReturnsNoResults() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _ in [] },
            fallbackSearch: { query, _ in
                [RecognizedArtist(id: "legacy", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
            }
        )

        let results = try await service.searchArtists(query: "Long Tail Artist")
        XCTAssertEqual(results.map(\.id), ["legacy"])
    }

    func testArtistSearchFallsBackWhenCatalogFails() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _ in throw ArtistSearchPolicyTestError.catalogUnavailable },
            fallbackSearch: { query, _ in
                [RecognizedArtist(id: "fallback", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
            }
        )

        let results = try await service.searchArtists(query: "Artist")
        XCTAssertEqual(results.map(\.id), ["fallback"])
    }

    func testArtistSearchSurfacesFallbackFailureInsteadOfPretendingNoResults() async {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _ in throw ArtistSearchPolicyTestError.catalogUnavailable },
            fallbackSearch: { _, _ in throw ArtistSearchError.rateLimited }
        )

        do {
            _ = try await service.searchArtists(query: "Artist")
            XCTFail("Expected search failure")
        } catch let error as ArtistSearchError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadingAutomaticallyConnectsArtistsAndBuildsSeparateShelves() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .multiFull)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertTrue(show.artists.allSatisfy { $0.appleMusicArtistID == nil })
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningFixtureCatalog(scenario: .multiFull),
                                           artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { _ in ListeningFixturePlayer() })
        defer { room.stop(); room.mechanism.motion.stop() }
        await room.load(show: show)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(show.artists.compactMap(\.appleMusicArtistID), ["fixture-artist-0", "fixture-artist-1"])
        XCTAssertEqual(show.artists.map(\.name), ["夜航", "海岸"])
        XCTAssertEqual(room.cabinetArtists.map(\.name), ["夜航", "海岸"])
        XCTAssertEqual(room.cabinetArtists.map { $0.albums.flatMap(\.tracks).count }, [4, 4])
        XCTAssertFalse(room.discs.isEmpty)
    }

    func testLateMatchCannotChangePreviousShowAfterSelectionChanges() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let first = try Show(name: "First", date: .now, startTime: .now)
        first.artists = [ArtistSlot(name: "Artist", avatarURL: nil)]
        let second = try Show(name: "Second", date: .now, startTime: .now)
        context.insert(first); context.insert(second); try context.save()
        let search = AutoMatchSearchStub(candidates: [candidate("late", "Artist")], delayed: true)
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningFixtureCatalog(scenario: .multiFull),
                                           artistSearchService: search, playbackFactory: { _ in ListeningFixturePlayer() })
        defer { room.stop(); room.mechanism.motion.stop() }
        let loading = Task { await room.load(show: first) }
        while await search.queries.isEmpty { await Task.yield() }
        await room.load(show: second)
        await loading.value
        XCTAssertEqual(room.show?.id, second.id)
        XCTAssertNil(first.artists.first?.appleMusicArtistID)
        XCTAssertTrue(room.discs.isEmpty)
    }

    func testOpenLidStaysInsideStageAndOutOfMetadata() {
        let geometry = CDPlayerConfiguration.standard.geometry
        let openEdge = geometry.hingeY + geometry.lid.height * cos((geometry.tiltDegrees + geometry.maximumOpening) * .pi / 180)
        XCTAssertGreaterThanOrEqual(openEdge, geometry.viewportTop)
        XCTAssertLessThan(geometry.maximumOpening, 90)
    }

    func testNormalRoomLoadUsesFreshCacheAndForceRefreshBypassesIt() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(name: "Cached Show", date: .now.addingTimeInterval(10000), startTime: .now.addingTimeInterval(10000))
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist-1")]
        context.insert(show)
        context.insert(CatalogSong(appleMusicSongID: "song-1", title: "Song", artistName: "Artist", duration: 100))
        context.insert(ArtistCatalogSnapshot(artistID: "artist-1", artistName: "Artist", orderedSongIDs: ["song-1"], topSongIDs: ["song-1"], albumIDs: []))
        try context.save()
        let catalog = CountingListenCatalog()
        let room = ListeningRoomCoordinator(context: context, catalogService: catalog, artistSearchService: AutoMatchSearchStub(candidates: []), playbackFactory: { _ in ListeningFixturePlayer() })
        defer { room.stop(); room.mechanism.motion.stop() }
        await room.load(show: show)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 0)
        await room.load(show: show)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 0)
        await room.load(show: show, force: true)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 1)
    }

    private func candidate(_ id: String, _ name: String) -> RecognizedArtist {
        RecognizedArtist(id: id, canonicalName: name, avatarURL: nil, appleMusicURL: nil)
    }
}

private enum ArtistSearchPolicyTestError: Error {
    case catalogUnavailable
    case unexpectedFallback
}

private actor AutoMatchSearchStub: ArtistSearchServicing {
    let candidates: [RecognizedArtist]
    let delayed: Bool
    private(set) var queries: [String] = []
    init(candidates: [RecognizedArtist], delayed: Bool = false) { self.candidates = candidates; self.delayed = delayed }
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        queries.append(query)
        if delayed { try await Task.sleep(for: .milliseconds(80)) }
        return candidates
    }
}

private final class CountingListenCatalog: ListeningMusicCatalogServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFetchCount = 0
    var fetchCount: Int { lock.withLock { storedFetchCount } }
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { .init(authorizationStatus: .authorized, canPlayCatalogContent: true) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        lock.withLock { storedFetchCount += 1 }
        return .init(artistID: artistID, artistName: "Artist", artworkURL: nil, editorialText: nil, genreNames: [],
                     orderedSongIDs: ["song-1"], topSongIDs: ["song-1"], albumIDs: [], songs: [], albums: [], fetchedAt: fetchedAt)
    }
}
