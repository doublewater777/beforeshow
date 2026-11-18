import XCTest
import SwiftData
import MusicKit
import os
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

    func testCatalogRankingWinsOverAnExactNameAndDraftAcceptsTheIdentity() async throws {
        let search = AutoMatchSearchStub(candidates: [
            candidate("band", "回春丹"), candidate("namesake", "回春丹乐队")
        ])
        let slots = [ArtistSlot(name: "回春丹乐队", avatarURL: nil)]
        let matches = await ShowDraftArtistAutoMatcher(search: search).matches(for: slots)
        let match = try XCTUnwrap(matches[0])
        XCTAssertEqual(match.id, "band", "The catalog's preferred artist must not be displaced by an exact-name namesake")
        var draft = ShowDraft(artists: slots)
        draft.attachArtistIdentity(match, at: 0)
        XCTAssertEqual(draft.artists[0].appleMusicArtistID, "band")
        XCTAssertEqual(draft.artists[0].name, "回春丹")
        let queries = await search.queries
        XCTAssertEqual(queries, ["回春丹乐队"], "Automatic matching searches only the original credit")
    }

    func testArtistSearchPreservesCatalogRankingForAliasesAndSuffixes() async throws {
        let catalogResults = [candidate("band", "回春丹"), candidate("namesake", "回春丹乐队")]
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in catalogResults },
            fallbackSearch: { _, _, _ in throw ArtistSearchPolicyTestError.unexpectedFallback }
        )
        let results = try await service.searchArtists(query: "回春丹乐队")
        XCTAssertEqual(results.map(\.id), ["band", "namesake"])
    }

    func testSearchRemovesArtistsWithoutAvatarsForBothCatalogAndPublicSearch() async throws {
        let missing = RecognizedArtist(id: "no-photo", canonicalName: "回春丹乐队", avatarURL: nil, appleMusicURL: nil)
        let photographed = RecognizedArtist(id: "band", canonicalName: "回春丹", avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil)
        for catalogAvailable in [true, false] {
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in
                    if !catalogAvailable { throw ArtistCatalogSearchError.accessUnavailable }
                    return [missing, photographed]
                },
                fallbackSearch: { _, _, _ in [missing, photographed] }
            )
            let results = try await service.searchArtists(query: "回春丹乐队")
            XCTAssertEqual(results.map(\.id), ["band"])
        }
    }

    func testTraditionalAndSimplifiedNamesCanAutoMatch() async throws {
        XCTAssertEqual(ArtistNameMatching.normalized("周杰倫"), ArtistNameMatching.normalized("周杰伦"))
        let results = try await ArtistIdentityMatcher(search: AutoMatchSearchStub(candidates: [candidate("jay", "周杰伦")]))
            .matches(for: [ArtistSlot(name: "周杰倫", avatarURL: nil)])
        XCTAssertEqual(results[0]?.id, "jay")
    }

    func testBilingualImportedArtistAutoLinksAndTakesAppleMusicName() async throws {
        let matched = candidate("sunset", "Sunset Rollercoaster")
        let results = try await ArtistIdentityMatcher(search: AutoMatchSearchStub(candidates: [matched]))
            .matches(for: [ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil)])
        XCTAssertEqual(results[0]?.id, "sunset")
        var draft = ShowDraft(artists: [ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil)])
        draft.attachArtistIdentity(matched, at: 0)
        XCTAssertEqual(draft.artists[0].appleMusicArtistID, "sunset")
        XCTAssertEqual(draft.artists[0].name, "Sunset Rollercoaster")
        XCTAssertTrue(draft.hasConfirmedArtistIdentity(draft.artists[0]))
    }

    func testMatchedArtistsTakeCachedAppleMusicNamesAcrossShowsAndTimetables() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(name: "Fest", date: .now, startTime: .now, artists: [
            ArtistSlot(name: "落日飞车 Sunset Rollercoaster", avatarURL: nil, appleMusicArtistID: "sunset"),
            ArtistSlot(name: "黄泽森", avatarURL: nil)
        ])
        context.insert(show)
        let performance = try TimetablePerformance(
            artistName: "落日飞车", startsAt: .now, endsAt: .now.addingTimeInterval(3600), appleMusicArtistID: "sunset"
        )
        context.insert(performance)
        context.insert(ArtistCatalogSnapshot(artistID: "sunset", artistName: "Sunset Rollercoaster"))
        try context.save()

        XCTAssertTrue(try ArtistAppleMusicName.sync(in: context))

        XCTAssertEqual(show.artists.map(\.name), ["Sunset Rollercoaster", "黄泽森"])
        XCTAssertEqual(show.artists[0].appleMusicArtistID, "sunset")
        XCTAssertEqual(performance.artistName, "Sunset Rollercoaster")
        XCTAssertFalse(try ArtistAppleMusicName.sync(in: context), "a second pass has nothing to rename")
    }

    func testOriginalCreditUsesThePreferredCatalogResultWithoutVariantQueries() async throws {
        for (credit, name) in [("jay zhou", "周杰倫"), ("Taylor Swfit", "Taylor Swift"),
                               ("落日飞车 Sunset Rollercoaster", "Sunset Rollercoaster")] {
            let search = AutoMatchSearchStub(candidates: [candidate("preferred", name)])
            let matches = try await ArtistIdentityMatcher(search: search).matches(for: [ArtistSlot(name: credit, avatarURL: nil)])
            XCTAssertEqual(matches[0]?.id, "preferred")
            let queries = await search.queries
            XCTAssertEqual(queries, [credit])
        }
    }

    func testFallbackCacheUsesResolvedRegionAndRefreshesWhenStorefrontChanges() async throws {
        let region = ArtistMarketTestState("JP")
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in throw ArtistCatalogSearchError.accessUnavailable },
            regionalFallbackSearch: { query, _, _, country in
                [await region.fallbackArtist(query: query, requestedCountry: country)]
            },
            countryResolver: { await region.currentCountry() }
        )
        let japan = try await service.searchArtists(query: "Region Artist")
        let cached = try await service.searchArtists(query: "Region Artist")
        XCTAssertEqual(japan.map(\.id), ["JP"])
        XCTAssertEqual(cached.map(\.id), ["JP"])
        let initialSearchCount = await region.searchCount()
        XCTAssertEqual(initialSearchCount, 1, "Same-region result should use the cache")

        await region.changeCountry("US")
        let usa = try await service.searchArtists(query: "Region Artist")
        XCTAssertEqual(usa.map(\.id), ["US"], "Changing storefront invalidates the prior market lookup")
        let updatedSearchCount = await region.searchCount()
        XCTAssertEqual(updatedSearchCount, 2)
        let requestedCountries = await region.requestedCountries()
        XCTAssertEqual(requestedCountries, ["JP", "US"],
                       "The actual iTunes country argument must match the cache market snapshot")
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
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: "ZZZ", musicStorefront: "JP", deviceRegion: "CN"), "JP")
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: "ZZZ", musicStorefront: nil, deviceRegion: "TW"), "TW")
        XCTAssertEqual(AppleMusicArtistSearchService.fallbackCountry(
            preferred: "ZZZ", musicStorefront: nil, deviceRegion: "001"), "US")
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

    func testDistinctOriginalScriptsKeepTheirOwnCatalogSearchResults() async throws {
        struct Search: ArtistSearchServicing {
            let results: [String: [RecognizedArtist]]
            func searchArtists(query: String) async throws -> [RecognizedArtist] { results[query] ?? [] }
        }
        let search = Search(results: [
            "周杰倫": [candidate("traditional-result", "周杰倫")],
            "周杰伦": [candidate("simplified-result", "周杰伦")]
        ])
        let matches = try await ArtistIdentityMatcher(search: search).matches(for: [
            ArtistSlot(name: "周杰倫", avatarURL: nil), ArtistSlot(name: "周杰伦", avatarURL: nil)
        ])
        XCTAssertEqual(matches[0]?.id, "traditional-result")
        XCTAssertEqual(matches[1]?.id, "simplified-result")
    }

    func testSameNameDifferentIDsStillRequireManualSelection() async throws {
        let search = AutoMatchSearchStub(candidates: [candidate("one", "回春丹"), candidate("two", "回春丹")])
        let matches = try await ArtistIdentityMatcher(search: search).matches(for: [ArtistSlot(name: "回春丹乐队", avatarURL: nil)])
        XCTAssertTrue(matches.isEmpty)
    }

    func testPublicSearchStillFiltersUnrelatedCandidates() async throws {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in throw ArtistCatalogSearchError.accessUnavailable },
            fallbackSearch: { _, _, _ in
                [RecognizedArtist(id: "2715720", canonicalName: "Kanye West", avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil),
                 RecognizedArtist(id: "unrelated", canonicalName: "Sia", avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil)]
            }
        )
        let results = try await service.searchArtists(query: "kanye")
        XCTAssertEqual(results.map(\.id), ["2715720"])
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

    func testAvailableCatalogResultsNeverMixInITunesIdentities() async throws {
        for catalogResults in [[], [candidate("similar", "姜思达工作室")], [candidate("other", "Different Artist")]] {
            let fallback = AutoMatchSearchStub(candidates: [candidate("itunes-only", "姜思达")])
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in catalogResults },
                fallbackSearch: { query, _, _ in try await fallback.searchArtists(query: query) }
            )
            let results = try await service.searchArtists(query: "姜思达")
            XCTAssertEqual(results, catalogResults)
            let queries = await fallback.queries
            XCTAssertTrue(queries.isEmpty, "An available MusicKit catalog owns the results, including misses")
        }
    }

    func testCatalogFailuresRemainRetryableWithoutSwitchingToITunes() async {
        let failures: [ArtistSearchError] = [.catalogUnavailable, .network, .rateLimited, .server(statusCode: 503), .decoding]
        for failure in failures {
            let fallback = AutoMatchSearchStub(candidates: [candidate("itunes-only", "Artist")])
            let service = AppleMusicArtistSearchService(
                catalogSearch: { _, _, _ in throw failure },
                fallbackSearch: { query, _, _ in try await fallback.searchArtists(query: query) }
            )
            do {
                _ = try await service.searchArtists(query: "Artist")
                XCTFail("A catalog failure must offer recovery instead of silently changing artist sources")
            } catch { XCTAssertEqual(error as? ArtistSearchError, failure) }
            let queries = await fallback.queries
            XCTAssertTrue(queries.isEmpty)
        }
    }

    func testArtistSearchSurfacesFallbackFailureInsteadOfPretendingNoResults() async {
        let service = AppleMusicArtistSearchService(
            catalogSearch: { _, _, _ in throw ArtistCatalogSearchError.accessUnavailable },
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

    func testInteractiveSearchWaitsForAuthorizationAndThenUsesMusicKitForTheSameQuery() async throws {
        let authorization = OSAllocatedUnfairLock(initialState: ListeningMusicAuthorizationStatus.notDetermined)
        let catalog = candidate("catalog-artist", "Artist")
        let service = AppleMusicArtistSearchService(
            catalogSearch: { query, _, _ in
                XCTAssertEqual(query, "Artist")
                return [catalog]
            },
            fallbackSearch: { _, _, _ in throw ArtistSearchPolicyTestError.unexpectedFallback },
            authorizationStatus: { authorization.withLock { $0 } }
        )
        for status in [ListeningMusicAuthorizationStatus.notDetermined, .denied, .restricted] {
            authorization.withLock { $0 = status }
            do {
                _ = try await service.searchInteractiveArtists(query: "Artist")
                XCTFail("Expected an authorization error")
            } catch let error as ArtistSearchError {
                XCTAssertEqual(error, .authorizationRequired(status))
            }
        }
        authorization.withLock { $0 = .authorized }
        let results = try await service.searchInteractiveArtists(query: "Artist")
        XCTAssertEqual(results.map(\.id), ["catalog-artist"])
    }

    func testPublicArtistSearchResolvesPortraitMetadataWhenITunesOmitsArtwork() async throws {
        try XCTSkipIf(MusicAuthorization.currentStatus == .authorized)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PublicArtistSearchProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let search = AppleMusicArtistSearchService(country: "US", session: session)
        let matches = try await ArtistIdentityMatcher(search: search).matches(for: [
            ArtistSlot(name: "Artist", avatarURL: nil)
        ])
        XCTAssertEqual(matches[0]?.id, "9000000000123")
        XCTAssertEqual(matches[0]?.avatarURL?.absoluteString, PublicArtistSearchProtocol.portrait)
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
                return [RecognizedArtist(id: "1483458284", canonicalName: query, avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil)]
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
        defer { room.stop() }
        await room.load(show: show)
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
        defer { room.stop() }

        await room.load(show: current)

        XCTAssertEqual(current.artists.first?.appleMusicArtistID, "12345")
        XCTAssertEqual(current.artists.first?.appleMusicURL, "https://music.apple.com/cn/artist/the-band/12345")
        // Unified artist avatars (#345): another show's unknown-source image is not copied across shows.
        XCTAssertNil(current.artists.first?.avatarURL)
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
        defer { room.stop() }

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
        defer { room.stop() }

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
        defer { room.stop() }
        let loading = Task { await room.load(show: first) }
        while await search.queries.isEmpty { await Task.yield() }
        await room.load(show: second)
        await loading.value
        XCTAssertEqual(room.show?.id, second.id)
        XCTAssertNil(first.artists.first?.appleMusicArtistID)
        XCTAssertTrue(room.discs.isEmpty)
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
        defer { room.stop() }

        await room.load(show: show)
        XCTAssertEqual(catalog.fetchCount, 0)

        await room.load(show: show, force: true)
        XCTAssertEqual(catalog.fetchCount, 0, "force refresh in all-artists scope must not pull the detailed artist catalog")

        room.selectScope(.artist("artist-1"))
        await room.reloadCatalog(force: true)
        XCTAssertEqual(catalog.fetchCount, 1, "selected artist force refresh may fetch that artist's detailed catalog")
    }

    private func candidate(_ id: String, _ name: String) -> RecognizedArtist {
        RecognizedArtist(id: id, canonicalName: name, avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil)
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

private actor ArtistMarketTestState {
    private var country: String
    private var countries: [String] = []

    init(_ country: String) { self.country = country }

    func currentCountry() -> String { country }
    func changeCountry(_ country: String) { self.country = country }
    func searchCount() -> Int { countries.count }
    func requestedCountries() -> [String] { countries }

    func fallbackArtist(query: String, requestedCountry: String) -> RecognizedArtist {
        countries.append(requestedCountry)
        return RecognizedArtist(id: requestedCountry, canonicalName: query,
                                avatarURL: URL(string: "https://example.com/portrait.jpg"), appleMusicURL: nil)
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

private final class PublicArtistSearchProtocol: URLProtocol, @unchecked Sendable {
    static let portrait = "https://is1-ssl.mzstatic.com/image/thumb/Features211/v4/portrait.png/486x486bb.png"

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch (url.host, url.path) {
        case ("itunes.apple.com", "/search"):
            body = """
                {"resultCount":2,"results":[
                  {"artistId":456,"artistName":"Artist","artistLinkUrl":"https://music.apple.com/us/artist/456?uo=4"},
                  {"artistId":9000000000123,"artistName":"Artist","artistLinkUrl":"https://music.apple.com/us/artist/9000000000123?uo=4"}
                ]}
                """
        case ("music.apple.com", "/us/artist/456"):
            body = """
                <head><script type="application/ld+json">
                  {"@type":"MusicAlbum","url":"https://music.apple.com/us/album/456",
                   "image":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/cover.jpg/486x486bb.png"}
                </script></head>
                """
        case ("music.apple.com", "/us/artist/9000000000123"):
            body = """
                <head><script type="application/ld+json">
                  {"@type":"MusicGroup","url":"https://music.apple.com/us/artist/9000000000123","image":"\(Self.portrait)"}
                </script></head>
                """
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
