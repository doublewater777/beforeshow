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
    func testNoDiscKeepsPlainTabsAcrossRootTabs() {
        for tab in BeforeShowTab.allCases {
            XCTAssertEqual(
                ListeningBottomChromeMode.resolve(selectedTab: tab, hasLoadedDisc: false),
                .tabsOnly
            )
        }
    }

    func testListenShowsFullPlayerWhenDiscIsLoaded() {
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .listen, hasLoadedDisc: true),
            .fullPlayer
        )
    }

    func testOtherTabsMorphListenTabIntoCompactPlayer() {
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .current, hasLoadedDisc: true),
            .compactPlayer
        )
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(selectedTab: .footprints, hasLoadedDisc: true),
            .compactPlayer
        )
    }

    func testRemovedDiscHidesChromeUntilDiscIsReseated() {
        let mechanism = CDMechanism()
        let song = CatalogSong(
            appleMusicSongID: "song",
            title: "Song",
            artistName: "Artist",
            duration: 180,
            previewURL: "https://example.invalid/song.m4a"
        )
        let disc = ListeningDisc(
            id: "disc",
            title: "Disc",
            artworkURL: nil,
            tracks: [ListeningDiscTrack(song)]
        )

        mechanism.restoreSeated(disc)
        XCTAssertTrue(mechanism.hasDisc)
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(
                selectedTab: .listen,
                hasLoadedDisc: mechanism.hasDisc
            ),
            .fullPlayer
        )

        // Opening the lid does not remove the disc; chrome remains available.
        mechanism.motion.lid.value = 1
        XCTAssertTrue(mechanism.isOpen)
        XCTAssertTrue(mechanism.hasDisc)
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(
                selectedTab: .current,
                hasLoadedDisc: mechanism.hasDisc
            ),
            .compactPlayer
        )

        mechanism.removeDisc()
        XCTAssertEqual(mechanism.position, .removed)
        XCTAssertNotNil(mechanism.disc, "Removed keeps the physical disc object while it is in hand")
        XCTAssertFalse(mechanism.hasDisc)
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(
                selectedTab: .listen,
                hasLoadedDisc: mechanism.hasDisc
            ),
            .tabsOnly
        )

        mechanism.restoreSeated(disc)
        XCTAssertTrue(mechanism.hasDisc)
        XCTAssertEqual(
            ListeningBottomChromeMode.resolve(
                selectedTab: .footprints,
                hasLoadedDisc: mechanism.hasDisc
            ),
            .compactPlayer
        )
        mechanism.motion.stop()
    }

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

    private func resetChromeGlobals() {
        ListeningPlaybackChromeStore.shared.room = nil
        ListeningRoomCache.shared?.mechanism.motion.stop()
        ListeningRoomCache.shared = nil
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
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

@MainActor
private final class ListeningChromePlaybackSpy: ListeningPlaybackServicing {
    private(set) var preparedSource: ListeningPlaybackSource?
    private(set) var prepareCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private var items: [ListeningPlaybackItem] = []
    private var index = 0
    private var playing = false

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

    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard items.indices.contains(index), let preparedSource else { return nil }
        let item = items[index]
        return ListeningPlaybackSample(
            songID: item.songID,
            source: preparedSource,
            currentTime: 0,
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
    }
}
