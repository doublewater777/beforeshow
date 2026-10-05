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
            title: "热门合辑 01",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)],
            origin: .compilation(showID: show.id, number: 1)
        )
        context.insert(
            ListeningLoadedDiscState(
                discData: try JSONEncoder().encode(disc),
                songID: song.appleMusicSongID
            )
        )
        try context.save()

        let playback = ListeningTestPlayer()
        var requestedSources: [ListeningPlaybackSource] = []
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { requestedSources.append($0); return playback }
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
        try await waitUntil { playback.prefetchedSongIDs == [song.appleMusicSongID] }
        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertEqual(requestedSources, [.fullCatalog])
        XCTAssertEqual(playback.loadCount, 1)
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
        XCTAssertEqual(playback.loadCount, 1)
        XCTAssertEqual(playback.pauseCount, 0)
        XCTAssertEqual(playback.stopCount, 0)
    }

    /// 小组件在 intent 返回后立刻刷新；返回时快照必须已翻转，否则按钮停在原状态。
    func testWidgetToggleFlipsSnapshotImmediatelyThenSettles() async throws {
        resetChromeGlobals()
        let widgetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-toggle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = widgetDirectory
        defer {
            resetChromeGlobals()
            WidgetSnapshotStore.overrideContainerURL = nil
            try? FileManager.default.removeItem(at: widgetDirectory)
        }

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Widget Toggle", date: now, startTime: now)
        context.insert(show)
        let song = CatalogSong(
            appleMusicSongID: "widget-song",
            title: "Widget Song",
            artistName: "Artist",
            duration: 180,
            previewURL: "https://example.invalid/widget.m4a"
        )
        let disc = ListeningDisc(
            id: "widget-disc",
            title: "热门合辑 01",
            artworkURL: URL(string: "https://example.invalid/disc.jpg"),
            tracks: [ListeningDiscTrack(song)],
            origin: .compilation(showID: show.id, number: 1)
        )
        context.insert(ListeningLoadedDiscState(discData: try JSONEncoder().encode(disc), songID: song.appleMusicSongID))
        try context.save()

        let playback = ListeningTestPlayer()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        defer { room.stop(); room.mechanism.motion.stop() }

        // intent 返回时快照已翻转（按键即时响应），真实播放随后落定且不回退
        await ListeningIntentHandler.shared.togglePlayPause()
        XCTAssertEqual(WidgetListeningStore.read()?.isPlaying, true)
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertEqual(WidgetListeningStore.read()?.isPlaying, true)
        XCTAssertEqual(WidgetListeningStore.read()?.coverImageURL, "https://example.invalid/disc.jpg")

        await ListeningIntentHandler.shared.togglePlayPause()
        XCTAssertEqual(WidgetListeningStore.read()?.isPlaying, false)
        try await waitUntil { !room.isPlaying }
        XCTAssertEqual(WidgetListeningStore.read()?.isPlaying, false)
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

        let playback = ListeningTestPlayer()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertEqual(playback.phase, .playing)
        XCTAssertEqual(playback.stopCount, 0)

        let cleared = await ListeningChromeBootstrapper.prepare(
            show: nil,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )

        XCTAssertNil(cleared)
        XCTAssertFalse(room.isPlaying)
        XCTAssertNotEqual(playback.phase, .playing)
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

    func testPreparingDifferentShowClearsVisibleErrorsFromPreviousShow() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let first = try Show(name: "First", date: .now, startTime: .now)
        let second = try Show(name: "Second", date: .now, startTime: .now)
        context.insert(first)
        context.insert(second)
        try context.save()

        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        room.prepareForDisplay(show: first)
        room.errorText = BSLocalization.text("保存失败，请重试")
        room.playbackError = BSLocalization.text("暂时无法播放")

        room.prepareForDisplay(show: second)

        XCTAssertNil(room.errorText)
        XCTAssertNil(room.playbackError)
        room.stop()
        room.mechanism.motion.stop()
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
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )

        XCTAssertNil(rootPrepared)
        XCTAssertNil(ListeningRoomCache.shared)
        XCTAssertNil(ListeningPlaybackChromeStore.shared.room)
        XCTAssertEqual(catalog.totalCallCount, 0, "Root bootstrap without a restored CD must not touch Music access/catalog")
        XCTAssertEqual(search.totalCallCount, 0, "Root bootstrap without a restored CD must not run artist matching")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 0)

        // The inactive tab may prepare its local room, but only activation can
        // begin music access, matching, or catalog enrichment.
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        ListeningRoomCache.shared = room
        room.setActive(false)
        room.prepareForDisplay(show: show)

        XCTAssertEqual(room.show?.id, show.id)
        XCTAssertTrue(room.initialLoaded)
        XCTAssertTrue(room.shouldReloadCatalog(for: show), "Local preparation must not mark enrichment complete")
        XCTAssertEqual(catalog.totalCallCount, catalog.authorizationStatusCount, "Inactive preparation may only read cached authorization status")
        XCTAssertEqual(search.totalCallCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 0)

        room.setActive(true)
        await room.load(show: show)

        XCTAssertEqual(room.show?.id, show.id)
        XCTAssertTrue(room.initialLoaded)
        XCTAssertGreaterThan(catalog.authorizationStatusCount, 0)
        XCTAssertGreaterThan(catalog.accessCount, 0)
        XCTAssertGreaterThan(search.searchCount, 0)
        XCTAssertGreaterThan(catalog.runtimeFetchCount, 0)
        XCTAssertEqual(catalog.fullFetchCount, 0, "Listen activation should stay on runtime topSongs until an artist browse scope needs full catalog")
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

        let playback = ListeningTestPlayer()
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

        // Lock Screen pause/play reach the system player directly; the shared
        // room reads them from the player with no view timer involved.
        playback.phase = .paused
        try await waitUntil { room.display.player.phase == .paused }
        XCTAssertFalse(room.isPlaying)

        playback.phase = .playing
        try await waitUntil { room.display.player.phase == .playing }
        XCTAssertTrue(room.isPlaying)

        // Lock Screen next moves the player's queue entry.
        playback.advanceNaturally()
        try await waitUntil { room.track?.id == "sync-b" }
        XCTAssertEqual(room.trackIndex, 1)

        // ApplicationMusicPlayer advancing on its own also updates chrome.
        playback.advanceNaturally()
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

        let playback = ListeningTestPlayer()
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
        room.deck.progressInterval = .milliseconds(20)

        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        // Progress samples arrive once a second while playing.
        playback.currentTime = 1.4
        try await Task.sleep(for: .milliseconds(150))
        playback.currentTime = 2.1
        try await waitUntil { room.errorText != nil }

        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .playing)
        XCTAssertFalse(room.actualSongIDs.contains(song.appleMusicSongID))
        XCTAssertFalse(room.familiarSongIDs.contains(song.appleMusicSongID))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        room.errorText = nil
        try await waitUntil { room.actualSongIDs.contains(song.appleMusicSongID) }

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

        let playback = ListeningTestPlayer()
        let prepared = await ListeningChromeBootstrapper.prepare(
            show: show,
            context: context,
            catalogService: ListeningChromeCatalogStub(),
            playbackFactory: { _ in playback }
        )
        let room = try XCTUnwrap(prepared)
        room.deck.progressInterval = .milliseconds(20)
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        room.playPause()
        try await waitUntil { room.isPlaying && !room.busy }
        XCTAssertFalse(room.actualSongIDs.contains(song.appleMusicSongID))
        XCTAssertFalse(room.familiarSongIDs.contains(song.appleMusicSongID))

        // Build continuous full-catalog evidence to just below 50% from the
        // deck's own progress samples, without any view timer.
        playback.currentTime = 1.4
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == song.appleMusicSongID }?.actualListeningAt
        )

        // A Lock Screen pause crosses 50%: the closing sample must persist and
        // re-project evidence into the shared room without a later tick.
        playback.currentTime = 2.1
        playback.phase = .paused

        try await waitUntil { !room.isPlaying }
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

    var searchCount: Int { locked { searches } }
    var totalCallCount: Int { locked { searches } }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        locked { searches += 1 }
        return [RecognizedArtist(id: "lazy-artist", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}


private enum CompatibilityEvidencePersistenceTestError: Error {
    case expectedFailure
}
