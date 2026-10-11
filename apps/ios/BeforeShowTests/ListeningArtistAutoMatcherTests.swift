import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningArtistAutoMatcherTests: XCTestCase {
    func testMatchesNamesWithoutOverwritingExistingIdentity() async throws {
        let search = AutoMatchSearchStub(candidates: [candidate("new", "  THE Band ")])
        let slots = [ArtistSlot(name: "the band", avatarURL: nil),
                     ArtistSlot(name: "the band", avatarURL: nil, appleMusicArtistID: "existing"),
                     ArtistSlot(name: "THE   Band", avatarURL: nil),
                     ArtistSlot(name: " \n ", avatarURL: nil)]
        let result = try await ArtistIdentityMatcher(search: search).matches(for: slots)
        XCTAssertEqual(result[0]?.id, "new")
        XCTAssertNil(result[1])
        XCTAssertEqual(result[2]?.id, "new")
        let queries = await search.queries
        XCTAssertEqual(queries, ["the band"])
    }

    func testTraditionalAndSimplifiedNamesCanAutoMatch() async throws {
        XCTAssertEqual(ArtistNameMatching.normalized("周杰倫"), ArtistNameMatching.normalized("周杰伦"))
        let results = try await ArtistIdentityMatcher(search: AutoMatchSearchStub(candidates: [candidate("jay", "周杰伦")]))
            .matches(for: [ArtistSlot(name: "周杰倫", avatarURL: nil)])
        XCTAssertEqual(results[0]?.id, "jay")
    }

    func testBilingualImportedArtistCanAutoLinkWithoutRewritingName() async throws {
        let matched = candidate("sunset", "Sunset Rollercoaster")
        let results = try await ArtistIdentityMatcher(search: AutoMatchSearchStub(candidates: [matched]))
            .matches(for: [ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil)])
        XCTAssertEqual(results[0]?.id, "sunset")
        var draft = ShowDraft(artists: [ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil)])
        draft.attachArtistIdentity(matched, at: 0)
        XCTAssertEqual(draft.artists[0].appleMusicArtistID, "sunset")
        XCTAssertEqual(draft.artists[0].name, "落日飞车 Sunset Rollercoaster")
    }

    func testLooseMatchingAcceptsPunctuationAndOneCharacterTypos() {
        XCTAssertEqual(ArtistNameMatching.uniqueConfidentMatch(
            for: "Panic at the Disco", among: [candidate("panic", "Panic! at the Disco")]
        )?.id, "panic")
        XCTAssertEqual(ArtistNameMatching.uniqueConfidentMatch(
            for: "Taylor Swfit", among: [candidate("taylor", "Taylor Swift")]
        )?.id, "taylor")
        XCTAssertNil(ArtistNameMatching.uniqueConfidentMatch(
            for: "姜思达", among: [candidate("studio", "姜思达工作室")]
        ))
        XCTAssertNil(ArtistNameMatching.uniqueConfidentMatch(
            for: "A B", among: [candidate("ab", "AB")]
        ))
    }

    func testAmbiguousBilingualMatchesStillRequireConfirmation() async throws {
        let results = try await ArtistIdentityMatcher(search: AutoMatchSearchStub(candidates: [
            candidate("one", "落日飞车"), candidate("two", "Sunset Rollercoaster")
        ])).matches(for: [ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil)])
        XCTAssertTrue(results.isEmpty)
    }

    func testTraditionalSearchRetriesSimplifiedNameWhenFirstResultIsOnlySimilar() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { query, _, _ in
                if query == "周杰倫" {
                    return [RecognizedArtist(id: "studio", canonicalName: "周杰伦工作室",
                                             avatarURL: nil, appleMusicURL: nil)]
                }
                return [RecognizedArtist(id: "artist", canonicalName: "周杰伦",
                                         avatarURL: nil, appleMusicURL: nil)]
            },
            fallbackSearch: { _, _, _ in [] }
        )
        let results = try await ArtistIdentityMatcher(search: service).matches(
            for: [ArtistSlot(name: "周杰倫", avatarURL: nil)]
        )
        XCTAssertEqual(results[0]?.id, "artist")
    }

    func testFallbackRegionUsesUserStorefrontOrDeviceRegion() {
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: nil, musicStorefront: "jp", deviceRegion: "CN"), "JP")
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: nil, musicStorefront: nil, deviceRegion: "tw"), "TW")
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: "GB", musicStorefront: "JP", deviceRegion: "CN"), "GB")
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: nil, musicStorefront: nil, deviceRegion: "001"), "US")
    }

    func testUsesExistingAppleMusicLinkWithoutSearch() async throws {
        let search = AutoMatchSearchStub(candidates: [])
        let slot = ArtistSlot(name: "Artist", avatarURL: nil, appleMusicURL: "https://music.apple.com/cn/artist/artist/12345")
        let result = try await ArtistIdentityMatcher(search: search).matches(for: [slot])
        XCTAssertEqual(result[0]?.id, "12345")
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testImportedArtistsReuseConfirmedLinksWithoutSearch() async {
        let search = AutoMatchSearchStub(candidates: [])
        let slot = ArtistSlot(name: "庄达菲", avatarURL: nil, appleMusicURL: "https://music.apple.com/cn/artist/1483458284")
        let result = await ShowDraftArtistAutoMatcher(search: search).matches(for: [slot])
        XCTAssertEqual(result[0]?.id, "1483458284")
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testAmbiguousAndUnrelatedSearchResultsDoNotAttachWrongArtist() async throws {
        let slots = [ArtistSlot(name: "Artist", avatarURL: nil)]
        let ambiguous = AutoMatchSearchStub(candidates: [candidate("one", "Artist"), candidate("two", "Artist")])
        let unrelated = AutoMatchSearchStub(candidates: [candidate("other", "Different Artist")])
        let first = try await ArtistIdentityMatcher(search: ambiguous).matches(for: slots)
        let second = try await ArtistIdentityMatcher(search: unrelated).matches(for: slots)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
    }

    func testInternalWhitespaceDifferenceDoesNotAutoMatch() async throws {
        let search = AutoMatchSearchStub(candidates: [candidate("wrong", "AB")])
        let result = try await ArtistIdentityMatcher(search: search).matches(for: [ArtistSlot(name: "A B", avatarURL: nil)])
        XCTAssertTrue(result.isEmpty)
    }

    func testArtistSearchReturnsRelevantCatalogCandidatesWithoutWaitingForFallback() async throws {
        for query in ["姜思达", "姜"] {
            let fallback = AutoMatchSearchStub(candidates: [])
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in
                    [RecognizedArtist(id: "1766242527", canonicalName: "姜思达", avatarURL: nil,
                                      appleMusicURL: URL(string: "https://music.apple.com/cn/artist/1766242527")),
                     RecognizedArtist(id: "unrelated", canonicalName: "Sia", avatarURL: nil, appleMusicURL: nil)]
                },
                fallbackSearch: { query, _, _ in try await fallback.searchArtists(query: query) }
            )
            let results = try await service.searchArtists(query: query)
            XCTAssertEqual(results.map(\.id), ["1766242527"])
            let queries = await fallback.queries
            XCTAssertTrue(queries.isEmpty)
        }

        let fallbackService = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in [] },
            fallbackSearch: { _, _, _ in
                [RecognizedArtist(id: "2715720", canonicalName: "Kanye West", avatarURL: nil, appleMusicURL: nil),
                 RecognizedArtist(id: "unrelated", canonicalName: "Sia", avatarURL: nil, appleMusicURL: nil)]
            }
        )
        let fallbackResults = try await fallbackService.searchArtists(query: "kanye")
        XCTAssertEqual(fallbackResults.map(\.id), ["2715720"])
    }

    func testRepeatedSearchReusesSuccessfulResultsAcrossNameFormatting() async throws {
        let catalog = AutoMatchSearchStub(candidates: [candidate("2715720", "Kanye West")])
        let service = AppleMusicArtistSearchService(
            catalogSearch: { query, _, _ in try await catalog.searchArtists(query: query) },
            fallbackSearch: { _, _, _ in throw ArtistSearchPolicyTestError.unexpectedFallback }
        )
        let first = try await service.searchArtists(query: "kanye west")
        let repeated = try await service.searchArtists(query: "  KANYE   WEST  ")
        XCTAssertEqual(first.map(\.id), ["2715720"])
        XCTAssertEqual(repeated, first)
        let exact = try await service.searchArtists(query: "Kanye West", exactMatchRequired: true)
        XCTAssertEqual(exact, first)
        let queries = await catalog.queries
        XCTAssertEqual(queries.count, 1)
    }

    func testFailedAndEmptySearchesRemainRetryable() async {
        for fails in [false, true] {
            let catalog = AutoMatchSearchStub(candidates: [])
            let service = AppleMusicArtistSearchService(
                catalogSearch: { query, _, _ in
                    let results = try await catalog.searchArtists(query: query)
                    if fails { throw ArtistSearchError.catalogUnavailable }
                    return results
                },
                fallbackSearch: { _, _, _ in [] }
            )
            for _ in 0..<2 { _ = try? await service.searchArtists(query: "庄达菲") }
            let queries = await catalog.queries
            XCTAssertEqual(queries.count, 2)
        }
    }

    func testCancelledSearchDoesNotStartFallbackAfterTransportCancellation() async throws {
        let gate = ArtistSearchRequestGate()
        let fallback = AutoMatchSearchStub(candidates: [candidate("unexpected", "Artist")])
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in
                await gate.wait()
                throw URLError(.cancelled)
            },
            fallbackSearch: { query, _, _ in try await fallback.searchArtists(query: query) }
        )
        let searching = Task { try await service.searchArtists(query: "Artist") }
        while !(await gate.started) { await Task.yield() }
        searching.cancel()
        await gate.release()
        do {
            _ = try await searching.value
            XCTFail("A superseded search must stop before its fallback request")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let queries = await fallback.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testArtistSearchFallsBackWhenCatalogReturnsNoResults() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in [] },
            fallbackSearch: { query, _, _ in
                [RecognizedArtist(id: "legacy", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
            }
        )

        let results = try await service.searchArtists(query: "Long Tail Artist")
        XCTAssertEqual(results.map(\.id), ["legacy"])
    }

    func testAutomaticMatchingContinuesSearchPastUnrelatedAndSimilarNames() async throws {
        for otherName in ["Different Artist", "姜思达工作室"] {
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in
                    [RecognizedArtist(id: "wrong", canonicalName: otherName, avatarURL: nil, appleMusicURL: nil)]
                },
                fallbackSearch: { query, _, _ in
                    [RecognizedArtist(id: "target", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
                }
            )
            _ = try await service.searchArtists(query: "姜思达")
            let matches = try await ArtistIdentityMatcher(search: service).matches(for: [ArtistSlot(name: "姜思达", avatarURL: nil)])
            XCTAssertEqual(matches[0]?.id, "target")
        }
    }

    func testArtistSearchFallsBackWhenCatalogFails() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in throw ArtistSearchPolicyTestError.catalogUnavailable },
            fallbackSearch: { query, _, _ in
                [RecognizedArtist(id: "fallback", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
            }
        )

        let results = try await service.searchArtists(query: "Artist")
        XCTAssertEqual(results.map(\.id), ["fallback"])
    }

    func testArtistSearchSurfacesFallbackFailureInsteadOfPretendingNoResults() async {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in throw ArtistSearchPolicyTestError.catalogUnavailable },
            fallbackSearch: { _, _, _ in throw ArtistSearchError.rateLimited }
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

    func testCatalogFailureWithEmptyFallbackPreservesRecoveryReason() async {
        let failures: [ArtistSearchError] = [.catalogUnavailable]
        for expected in failures {
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in throw expected },
                fallbackSearch: { _, _, _ in [] }
            )
            do {
                _ = try await service.searchArtists(query: "庄达菲")
                XCTFail("An unavailable catalog plus an empty iTunes index cannot confirm absence")
            } catch let actual as ArtistSearchError {
                XCTAssertEqual(actual, expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnavailableCatalogAccessUsesPublicSearchWithoutAuthorization() async throws {
        for candidates in [[], [candidate("public", "Artist")]] {
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in throw ArtistCatalogSearchError.accessUnavailable },
                fallbackSearch: { _, _, _ in candidates }
            )
            let results = try await service.searchArtists(query: "Artist")
            XCTAssertEqual(results, candidates)
        }
    }

    func testEmptyCatalogWithFailedFallbackPreservesSearchFailure() async {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in [] },
            fallbackSearch: { _, _, _ in throw ArtistSearchError.rateLimited }
        )
        do {
            _ = try await service.searchArtists(query: "庄达菲")
            XCTFail("An empty catalog must not hide a failed fallback")
        } catch ArtistSearchError.rateLimited {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulEmptySourcesCanConfirmNoResults() async throws {
        let service = AppleMusicArtistSearchService(catalogSearch: { _, _, _ in [] }, fallbackSearch: { _, _, _ in [] })
        let results = try await service.searchArtists(query: "Unknown Artist")
        XCTAssertTrue(results.isEmpty)
    }

    func testOneFailedArtistDoesNotDiscardOtherResolvedIdentities() async throws {
        let search = AppleMusicArtistSearchService(
            catalogSearch: { query, _, _ in
                guard query != "Unavailable" else { throw ArtistSearchPolicyTestError.catalogUnavailable }
                return [RecognizedArtist(id: "1483458284", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
            },
            fallbackSearch: { _, _, _ in throw ArtistSearchError.network }
        )
        let slots = [ArtistSlot(name: "庄达菲", avatarURL: nil), ArtistSlot(name: "Unavailable", avatarURL: nil)]
        let result = try await ArtistIdentityMatcher(search: search).matches(for: slots)
        XCTAssertEqual(result[0]?.id, "1483458284")
        XCTAssertNil(result[1])
    }

    func testLoadingAutomaticallyConnectsArtistsAndBuildsSeparateShelves() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .multiFull)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertTrue(show.artists.allSatisfy { $0.appleMusicArtistID == nil })
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningFixtureCatalog(scenario: .multiFull),
                                           artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { ListeningFixturePlayer(source: $0) })
        defer { room.stop(); room.mechanism.motion.stop() }
        await room.load(show: show)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(show.artists.compactMap(\.appleMusicArtistID), ["fixture-artist-0", "fixture-artist-1"])
        XCTAssertEqual(show.artists.map(\.name), ["夜航", "海岸"])
        XCTAssertEqual(room.cabinetArtists.map(\.name), ["夜航", "海岸"])
        XCTAssertEqual(room.cabinetArtists.map { $0.albums.flatMap(\.tracks).count }, [4, 4])
        XCTAssertFalse(room.discs.isEmpty)
    }

    func testLoadingReusesKnownArtistIdentityAcrossShowsWithoutSearch() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let previous = try Show(name: "Previous", date: .now, startTime: .now)
        previous.artists = [
            ArtistSlot(
                name: "  THE Band ",
                avatarURL: "https://example.com/artist.jpg",
                appleMusicURL: "https://music.apple.com/cn/artist/the-band/12345",
                appleMusicArtistID: "12345"
            )
        ]
        let current = try Show(name: "Current", date: .now, startTime: .now)
        current.artists = [ArtistSlot(name: "the band", avatarURL: nil)]
        context.insert(previous)
        context.insert(current)
        try context.save()

        let search = AutoMatchSearchStub(candidates: [])
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: CountingListenCatalog(),
            artistSearchService: search,
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer { room.stop(); room.mechanism.motion.stop() }

        await room.load(show: current)

        XCTAssertEqual(current.artists.first?.appleMusicArtistID, "12345")
        XCTAssertEqual(current.artists.first?.appleMusicURL, "https://music.apple.com/cn/artist/the-band/12345")
        XCTAssertEqual(current.artists.first?.avatarURL, "https://example.com/artist.jpg")
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testLoadingDoesNotReuseConflictingArtistIdentitiesAcrossShows() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        for (name, id) in [("First", "one"), ("Second", "two")] {
            let show = try Show(name: name, date: .now, startTime: .now)
            show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: id)]
            context.insert(show)
        }
        let current = try Show(name: "Current", date: .now, startTime: .now)
        current.artists = [ArtistSlot(name: "Artist", avatarURL: nil)]
        context.insert(current)
        try context.save()

        let search = AutoMatchSearchStub(candidates: [])
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: CountingListenCatalog(),
            artistSearchService: search,
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer { room.stop(); room.mechanism.motion.stop() }

        await room.load(show: current)

        XCTAssertNil(current.artists.first?.appleMusicArtistID)
        let queries = await search.queries
        XCTAssertEqual(queries, ["Artist"])
    }

    func testLoadingPreservesCurrentArtistLinkOverSameNamedHistoricalIdentity() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let previous = try Show(name: "Previous", date: .now, startTime: .now)
        previous.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "12345")]
        let current = try Show(name: "Current", date: .now, startTime: .now)
        let currentURL = "https://music.apple.com/cn/artist/artist/67890"
        current.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicURL: currentURL)]
        context.insert(previous)
        context.insert(current)
        try context.save()

        let search = AutoMatchSearchStub(candidates: [])
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: CountingListenCatalog(),
            artistSearchService: search,
            playbackFactory: { ListeningFixturePlayer(source: $0) }
        )
        defer { room.stop(); room.mechanism.motion.stop() }

        await room.load(show: current)

        XCTAssertEqual(current.artists.first?.appleMusicArtistID, "67890")
        XCTAssertEqual(current.artists.first?.appleMusicURL, currentURL)
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
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
                                           artistSearchService: search, playbackFactory: { ListeningFixturePlayer(source: $0) })
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

    func testAllArtistsForceRefreshStaysLazyUntilSelectedArtistRefresh() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(name: "Cached Show", date: .now.addingTimeInterval(10000), startTime: .now.addingTimeInterval(10000))
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist-1")]
        context.insert(show)
        context.insert(CatalogSong(appleMusicSongID: "song-1", title: "Song", artistName: "Artist", duration: 100))
        context.insert(ArtistCatalogSnapshot(artistID: "artist-1", artistName: "Artist", orderedSongIDs: ["song-1"], topSongIDs: ["song-1"], albumIDs: []))
        try context.save()
        let catalog = CountingListenCatalog()
        let room = ListeningRoomCoordinator(context: context, catalogService: catalog, artistSearchService: AutoMatchSearchStub(candidates: []), playbackFactory: { ListeningFixturePlayer(source: $0) })
        defer { room.stop(); room.mechanism.motion.stop() }

        await room.load(show: show)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 0)

        await room.load(show: show, force: true)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 0, "force refresh in all-artists scope must not pull the detailed artist catalog")

        room.selectScope(.artist("artist-1"))
        await room.reloadCatalog(force: true)
        try await ListenTestData.settle(room) { !room.busy }
        XCTAssertEqual(catalog.fetchCount, 1, "selected artist force refresh may fetch that artist's detailed catalog")
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

private actor ArtistSearchRequestGate {
    private(set) var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { waiter?.resume(); waiter = nil }
}
