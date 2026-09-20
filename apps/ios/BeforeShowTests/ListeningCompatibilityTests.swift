import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningCompatibilityTests: XCTestCase {
    func testArtistSlotDecodesPreArtistIDPayload() throws {
        let data = Data(#"{"name":"Artist","avatarURL":null,"appleMusicURL":"https://music.apple.com/cn/artist/name/123","albumArtworkURL":null}"#.utf8)

        let decoded = try JSONDecoder().decode(ArtistSlot.self, from: data)

        XCTAssertEqual(decoded.name, "Artist")
        XCTAssertEqual(decoded.appleMusicURL, "https://music.apple.com/cn/artist/name/123")
        XCTAssertNil(decoded.appleMusicArtistID)
    }

    func testManualUndoDoesNotRemoveActualEvidence() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let manualAt = Date(timeIntervalSince1970: 100)
        let actualAt = Date(timeIntervalSince1970: 200)

        _ = try repository.confirmManualFamiliarity(songID: "song", at: manualAt)
        _ = try repository.confirmActualFamiliarity(songID: "song", at: actualAt)
        try repository.undoManualFamiliarity(songID: "song", at: Date(timeIntervalSince1970: 300))
        try context.save()

        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        let stored = try XCTUnwrap(records.first)
        XCTAssertNil(stored.manualConfirmedAt)
        XCTAssertEqual(stored.actualListeningAt, actualAt)
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "song",
            records: records,
            setlistMemories: []
        ))
    }

    func testOrphanRepairRemovesOnlyShowScopedListeningRows() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let missingShowID = UUID()
        let now = Date()
        context.insert(ShowWantsLiveSong(showID: missingShowID, songID: "song"))
        context.insert(ShowArtistListeningPreference(showID: missingShowID, artistID: "artist", isExcluded: true))
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: missingShowID,
            effectiveStartAtCapture: now,
            familiarSongIDsAtCapture: ["song"]
        ))
        context.insert(ShowOpeningArtistTier(
            showID: missingShowID,
            artistID: "artist",
            artistNameAtCapture: "Artist",
            tierRawValue: "familiar",
            baselineCapturedAt: now,
            catalogSnapshotFetchedAt: now
        ))
        context.insert(ShowSetlistMemory(showID: missingShowID, catalogSongID: "song"))
        context.insert(SongFamiliarityRecord(songID: "song", actualListeningAt: now))
        context.insert(CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist"))
        try context.save()

        try ListeningShowDataCleaner.deleteOrphans(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 1)
    }
}

@MainActor
final class ListeningMiniPlayerChromeTests: XCTestCase {
    func testColdStartHydratesCachedCoordinatorBeforeCompactPlaybackAndListenAdoptsIt() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Cold Start", date: now, startTime: now)
        context.insert(show)

        let song = CatalogSong(
            appleMusicSongID: "cold-song",
            title: "Cold Song",
            artistName: "Artist",
            duration: 180,
            previewURL: "https://example.invalid/cold.m4a"
        )
        let disc = ListeningDisc(
            id: "cold-disc",
            title: "Cold Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let playback = ListeningChromePlaybackSpy()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        XCTAssertTrue(ListeningRoomCache.shared.map { $0 === room } == true)
        XCTAssertTrue(ListeningPlaybackChromeStore.shared.room.map { $0 === room } == true)
        XCTAssertEqual(room.show?.id, show.id)
        XCTAssertTrue(room.mechanism.hasDisc)
        XCTAssertEqual(room.track?.id, song.appleMusicSongID)
        XCTAssertFalse(room.isPlaying, "Cold-start hydration must never autoplay")
        XCTAssertFalse(room.shouldReloadCatalog(for: show))

        // Compact play before visiting Listen must use hydrated Music access rather
        // than the coordinator's initial notDetermined/preview fallback.
        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertEqual(playback.preparedSource, .fullCatalog)
        XCTAssertEqual(playback.prepareCount, 1)
        XCTAssertEqual(playback.pauseCount, 0)
        XCTAssertEqual(playback.stopCount, 0)

        // This is the exact adoption predicate used by ListenRootView. It must keep
        // the same coordinator/transport and must not prepare a second player.
        let listenRoom = try XCTUnwrap(ListeningRoomCache.shared)
        XCTAssertTrue(listenRoom === room)
        if listenRoom.shouldReloadCatalog(for: show) {
            await listenRoom.load(show: show)
        }
        XCTAssertTrue(listenRoom.isPlaying)
        XCTAssertEqual(listenRoom.track?.id, song.appleMusicSongID)
        XCTAssertEqual(listenRoom.trackIndex, room.trackIndex)
        XCTAssertEqual(playback.prepareCount, 1)
        XCTAssertEqual(playback.pauseCount, 0)
        XCTAssertEqual(playback.stopCount, 0)
    }

    func testClearingCurrentShowStopsCachedPlaybackAndPreservesRestoredDisc() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Cleared Current", date: now, startTime: now)
        context.insert(show)

        let song = CatalogSong(
            appleMusicSongID: "cleared-song",
            title: "Cleared Song",
            artistName: "Artist",
            duration: 180,
            previewURL: "https://example.invalid/cleared.m4a"
        )
        let disc = ListeningDisc(
            id: "cleared-disc",
            title: "Cleared Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let playback = ListeningChromePlaybackSpy()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertTrue(playback.transportIsPlaying)
        XCTAssertEqual(playback.stopCount, 0)

        let cleared = await ListeningChromeBootstrapper.prepare(
            show: nil,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )

        XCTAssertNil(cleared)
        XCTAssertFalse(room.isPlaying)
        XCTAssertFalse(playback.transportIsPlaying)
        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertNil(ListeningRoomCache.shared)
        XCTAssertNil(ListeningPlaybackChromeStore.shared.room)

        let persisted = try context.fetch(FetchDescriptor<ListeningLoadedDiscState>())
        XCTAssertEqual(persisted.count, 1, "Clearing Current Show stops runtime playback but keeps the restored CD snapshot")
        let persistedState = try XCTUnwrap(persisted.first)
        let restored = try JSONDecoder().decode(ListeningDisc.self, from: persistedState.discData)
        XCTAssertEqual(restored.id, disc.id)
        XCTAssertEqual(persistedState.songID, song.appleMusicSongID)
    }

    func testRootBootstrapWithoutRestoredDiscStaysLazyUntilListenActivation() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Lazy Root", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil)]
        context.insert(show)
        try context.save()

        let catalog = ListeningChromeCatalogPipelineSpy()
        let search = ListeningChromeArtistSearchSpy()
        let rootPrepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningChromePlaybackSpy() }
        )

        XCTAssertNil(rootPrepared)
        XCTAssertNil(ListeningRoomCache.shared)
        XCTAssertNil(ListeningPlaybackChromeStore.shared.room)
        XCTAssertEqual(catalog.totalCallCount, 0, "Root bootstrap without a restored CD must not touch Music access/catalog")
        XCTAssertEqual(search.totalCallCount, 0, "Root bootstrap without a restored CD must not run artist matching")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 0)

        // Simulate the normal Listen activation path: only now create/cache a room
        // and execute its standard load pipeline.
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningChromePlaybackSpy() }
        )
        ListeningRoomCache.shared = room
        await room.load(show: show)

        XCTAssertEqual(room.show?.id, show.id)
        XCTAssertTrue(room.initialLoaded)
        XCTAssertGreaterThan(catalog.authorizationStatusCount, 0)
        XCTAssertGreaterThan(catalog.accessCount, 0)
        XCTAssertGreaterThan(search.searchCount, 0)
        XCTAssertGreaterThan(catalog.runtimeFetchCount, 0)
        XCTAssertGreaterThan(catalog.fullFetchCount, 0)
        XCTAssertTrue(room.catalogSongs.contains { $0.appleMusicSongID == "lazy-song" })
        room.stop()
        room.mechanism.motion.stop()
    }

    func testGlobalChromeTracksRemoteAndNaturalTransportChangesWithoutRoomTick() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Sync Show", date: now, startTime: now)
        context.insert(show)

        let songs = ["sync-a", "sync-b", "sync-c"].map { id in
            CatalogSong(
                appleMusicSongID: id,
                title: id.uppercased(),
                artistName: "Artist",
                duration: 180,
                previewURL: nil
            )
        }
        let disc = ListeningDisc(
            id: "sync-disc",
            title: "Sync Disc",
            artworkURL: nil,
            tracks: songs.map(ListeningDiscTrack.init)
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: "sync-a"
            )
        )
        try context.save()

        let playback = ListeningChromePlaybackSpy()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertEqual(room.track?.id, "sync-a")

        // Remote pause/play updates the shared room immediately; no ListeningRoomView
        // timer or explicit room.tick() is involved.
        try await ListeningRemoteCommandBridge.shared.togglePlayPauseForTesting()
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .paused)

        try await ListeningRemoteCommandBridge.shared.togglePlayPauseForTesting()
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .playing)

        // Remote next also projects the controller's new queue entry immediately.
        try await ListeningRemoteCommandBridge.shared.nextForTesting()
        XCTAssertEqual(room.track?.id, "sync-b")
        XCTAssertEqual(room.trackIndex, 1)

        // Simulate ApplicationMusicPlayer naturally advancing while Listen is not
        // driving a view timer. The controller observation must still update chrome.
        playback.advanceTransportToNext()
        try await waitUntil { room.track?.id == "sync-c" }
        XCTAssertEqual(room.trackIndex, 2)
        XCTAssertTrue(room.isPlaying)

        let persisted = try XCTUnwrap(context.fetch(FetchDescriptor<ListeningLoadedDiscState>()).first)
        XCTAssertEqual(persisted.songID, "sync-c")
    }

    func testEvidencePersistenceFailureRetriesAndEventuallyUpdatesRoomProjection() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Evidence Retry", date: now, startTime: now)
        context.insert(show)

        let song = CatalogSong(
            appleMusicSongID: "retry-song",
            title: "Retry Song",
            artistName: "Artist",
            duration: 4,
            previewURL: nil
        )
        let disc = ListeningDisc(
            id: "retry-disc",
            title: "Retry Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let playback = ListeningChromePlaybackSpy()
        var shouldFail = true
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        if shouldFail {
                            shouldFail = false
                            throw CompatibilityEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }
        await room.load(show: show)

        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        playback.currentTime = 1.4
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting()
        playback.currentTime = 2.1
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting()

        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .playing)
        XCTAssertNotNil(room.errorText)
        XCTAssertFalse(room.actualSongIDs.contains(song.appleMusicSongID))
        XCTAssertFalse(room.familiarSongIDs.contains(song.appleMusicSongID))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        room.errorText = nil
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting()

        XCTAssertTrue(room.isPlaying)
        XCTAssertNil(room.errorText)
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == song.appleMusicSongID }
        )
        XCTAssertNotNil(record.actualListeningAt)
        XCTAssertTrue(room.actualSongIDs.contains(song.appleMusicSongID))
        XCTAssertTrue(room.familiarSongIDs.contains(song.appleMusicSongID))
    }

    func testRemotePauseThresholdImmediatelyProjectsPersistedEvidenceWithoutRoomTick() async throws {
        resetChromeGlobals()
        defer { resetChromeGlobals() }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Evidence Sync", date: now, startTime: now)
        context.insert(show)

        let song = CatalogSong(
            appleMusicSongID: "threshold-song",
            title: "Threshold Song",
            artistName: "Artist",
            duration: 4,
            previewURL: nil
        )
        let disc = ListeningDisc(
            id: "threshold-disc",
            title: "Threshold Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let playback = ListeningChromePlaybackSpy()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertFalse(room.actualSongIDs.contains(song.appleMusicSongID))
        XCTAssertFalse(room.familiarSongIDs.contains(song.appleMusicSongID))

        // Build continuous full-catalog evidence to just below 50% without using
        // the ListeningRoomView timer or room.tick().
        playback.currentTime = 1.4
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting()
        XCTAssertNil(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == song.appleMusicSongID }?.actualListeningAt
        )

        // The final remote-pause sample crosses 50%. pause() stops controller
        // observation, so this sample must both persist and immediately re-project
        // evidence into the shared room without a later polling tick.
        playback.currentTime = 2.1
        try ListeningRemoteCommandBridge.shared.pauseForTesting()

        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .paused)
        try await waitUntil {
            room.actualSongIDs.contains(song.appleMusicSongID)
                && room.familiarSongIDs.contains(song.appleMusicSongID)
        }
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == song.appleMusicSongID }
        )
        XCTAssertNotNil(record.actualListeningAt)
    }

    private func resetChromeGlobals() {
        ListeningPlaybackChromeStore.shared.room = nil
        ListeningRoomCache.shared?.mechanism.motion.stop()
        ListeningRoomCache.shared = nil
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for listening chrome playback")
    }
}

private struct ListeningChromeCatalogStub: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }

    func currentAccess() async -> ListeningMusicAccess {
        ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

private final class ListeningChromeCatalogPipelineSpy: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var authorizationStatusCalls = 0
    private var authorizationRequestCalls = 0
    private var accessCalls = 0
    private var runtimeFetchCalls = 0
    private var fullFetchCalls = 0

    var authorizationStatusCount: Int { locked { authorizationStatusCalls } }
    var accessCount: Int { locked { accessCalls } }
    var runtimeFetchCount: Int { locked { runtimeFetchCalls } }
    var fullFetchCount: Int { locked { fullFetchCalls } }
    var totalCallCount: Int {
        locked {
            authorizationStatusCalls + authorizationRequestCalls + accessCalls + runtimeFetchCalls + fullFetchCalls
        }
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        locked { authorizationStatusCalls += 1 }
        return .authorized
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        locked { authorizationRequestCalls += 1 }
        return .authorized
    }

    func currentAccess() async -> ListeningMusicAccess {
        locked { accessCalls += 1 }
        return ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        locked { runtimeFetchCalls += 1 }
        return [songPayload(artistID: artistID)]
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        locked { fullFetchCalls += 1 }
        let song = songPayload(artistID: artistID)
        return ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: "Artist",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: [song.songID],
            topSongIDs: [song.songID],
            albumIDs: [],
            songs: [song],
            albums: [],
            fetchedAt: fetchedAt
        )
    }

    private func songPayload(artistID: String) -> ListeningCatalogSongPayload {
        ListeningCatalogSongPayload(
            songID: "lazy-song",
            title: "Lazy Song",
            artistName: "Artist",
            albumID: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: 180,
            performerArtistIDs: [artistID],
            performerArtistNames: ["Artist"],
            previewURL: nil
        )
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class ListeningChromeArtistSearchSpy: @unchecked Sendable, ArtistSearchServicing {
    private let lock = NSLock()
    private var searches = 0
    private var authorizationRequests = 0

    var searchCount: Int { locked { searches } }
    var totalCallCount: Int { locked { searches + authorizationRequests } }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        locked { searches += 1 }
        return [RecognizedArtist(id: "lazy-artist", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus {
        locked { authorizationRequests += 1 }
        return .authorized
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
private final class ListeningChromePlaybackSpy: ListeningPlaybackServicing {
    private(set) var preparedSource: ListeningPlaybackSource?
    private(set) var prepareCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private var items: [ListeningPlaybackItem] = []
    private var index = 0
    private var playing = false
    private var transportContinuation: AsyncStream<ListeningPlaybackSample>.Continuation?
    var currentTime: TimeInterval = 0

    var transportIsPlaying: Bool { playing }

    private var pendingSamples: [ListeningPlaybackSample] = []

    func advanceTransportToNext() {
        guard index + 1 < items.count else { return }
        index += 1
        emitTransport()
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        self.items = items
        preparedSource = source
        index = startingAtSongID.flatMap { id in
            items.firstIndex(where: { $0.songID == id })
        } ?? 0
        prepareCount += 1
        currentTime = 0
        playing = false
    }

    func play() async throws {
        playing = true
    }

    func pause() {
        pauseCount += 1
        playing = false
    }

    func skipToNext() async throws {
        guard index + 1 < items.count else { throw ListeningPlaybackError.queueBoundary }
        index += 1
    }

    func skipToPrevious() async throws {
        guard index > 0 else { throw ListeningPlaybackError.queueBoundary }
        index -= 1
    }

    func seek(to time: TimeInterval) {}

    func transportEvents() -> AsyncStream<ListeningPlaybackSample> {
        AsyncStream { continuation in
            transportContinuation = continuation
            for sample in pendingSamples {
                continuation.yield(sample)
            }
            pendingSamples.removeAll()
        }
    }

    private func emitTransport(observedAt: Date = Date()) {
        guard let sample = snapshot(observedAt: observedAt) else { return }
        if let transportContinuation {
            transportContinuation.yield(sample)
        } else {
            pendingSamples.append(sample)
        }
    }

    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard items.indices.contains(index), let preparedSource else { return nil }
        let item = items[index]
        return ListeningPlaybackSample(
            songID: item.songID,
            source: preparedSource,
            currentTime: currentTime,
            duration: item.duration,
            isPlaying: playing,
            observedAt: observedAt
        )
    }

    func stop() {
        stopCount += 1
        playing = false
        items = []
        index = 0
        currentTime = 0
        transportContinuation?.finish()
        transportContinuation = nil
    }
}

private enum CompatibilityEvidencePersistenceTestError: Error {
    case expectedFailure
}
