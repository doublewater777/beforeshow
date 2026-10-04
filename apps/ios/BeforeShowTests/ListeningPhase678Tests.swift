import Foundation
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

private final class OutOfOrderMusicAccessCatalog: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var nextRequestID = 0
    private var continuations: [Int: CheckedContinuation<ListeningMusicAccess, Never>] = [:]

    var pendingRequestIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return continuations.keys.sorted()
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        .authorized
    }

    func currentAccess() async -> ListeningMusicAccess {
        await withCheckedContinuation { continuation in
            lock.lock()
            nextRequestID += 1
            continuations[nextRequestID] = continuation
            lock.unlock()
        }
    }

    func resume(requestID: Int, with access: ListeningMusicAccess) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: requestID)
        lock.unlock()
        continuation?.resume(returning: access)
    }

    func resumeAll(with access: ListeningMusicAccess) {
        lock.lock()
        let pending = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: access) }
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

private final class AuthorizationTransitionCatalog: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var status: ListeningMusicAuthorizationStatus
    private var playbackAccess: ListeningCatalogPlaybackAccess
    private var fullFetches = 0

    init(
        status: ListeningMusicAuthorizationStatus = .notDetermined,
        playbackAccess: ListeningCatalogPlaybackAccess = .available
    ) {
        self.status = status
        self.playbackAccess = playbackAccess
    }

    private func readState() -> (
        ListeningMusicAuthorizationStatus,
        ListeningCatalogPlaybackAccess
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (status, playbackAccess)
    }

    func setStatusForTesting(_ value: ListeningMusicAuthorizationStatus) {
        lock.lock()
        status = value
        lock.unlock()
    }

    func setPlaybackAccessForTesting(_ value: ListeningCatalogPlaybackAccess) {
        lock.lock()
        playbackAccess = value
        lock.unlock()
    }

    var fullFetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fullFetches
    }

    private func recordFullFetch() {
        lock.lock()
        fullFetches += 1
        lock.unlock()
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        readState().0
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        setStatusForTesting(.authorized)
        return .authorized
    }

    func currentAccess() async -> ListeningMusicAccess {
        let (current, currentPlaybackAccess) = readState()
        return .init(
            authorizationStatus: current,
            catalogPlaybackAccess: current == .authorized ? currentPlaybackAccess : .accountLimited
        )
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        recordFullFetch()

        let songIDs: [String]
        let albumIDs: [String]
        let artistName: String
        switch artistID {
        case "a":
            songIDs = ["a1", "a2"]
            albumIDs = ["album"]
            artistName = "A"
        case "c":
            songIDs = ["c1"]
            albumIDs = []
            artistName = "C"
        default:
            songIDs = (0..<4).map { "fixture-song-0-\($0)" }
            albumIDs = ["fixture-album-0"]
            artistName = "Aimer"
        }

        return ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: artistName,
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: songIDs,
            topSongIDs: Array(songIDs.prefix(2)),
            albumIDs: albumIDs,
            songs: [],
            albums: [],
            fetchedAt: fetchedAt
        )
    }
}

private final class CountingArtistSearchService: @unchecked Sendable, ArtistSearchServicing {
    private let lock = NSLock()
    private var searches = 0
    private let result: RecognizedArtist?

    init(result: RecognizedArtist? = nil) {
        self.result = result
    }

    private func recordSearch() {
        lock.lock()
        searches += 1
        lock.unlock()
    }

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return searches
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        recordSearch()
        return result.map { [$0] } ?? []
    }

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
}
final class ListeningAccessibilityTests: XCTestCase {
    func testUserPauseNeverResumesFromLifecycle() {
        var policy = ListeningVisibilityPolicy()
        policy.interrupt(wasPlaying: true)
        XCTAssertTrue(policy.resumeIfAllowed())
        policy.userPause(); policy.interrupt(wasPlaying: true)
        XCTAssertFalse(policy.resumeIfAllowed())
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .fullCatalog))
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .preview))
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: false, foreground: true, source: .fullCatalog))
    }
}

@MainActor final class ListeningLoadingPipelineTests: XCTestCase {
    func testAuthorizationContinuesCatalogWithoutRepeatingArtistMatching() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(10_000)
        let show = try Show(name: "First Show", date: start, startTime: start)
        show.artists = [ArtistSlot(name: "Unmatched Artist", avatarURL: nil)]
        context.insert(show)
        try context.save()

        let catalog = AuthorizationTransitionCatalog()
        let search = CountingArtistSearchService(result: RecognizedArtist(
            id: "unmatched-artist-id",
            canonicalName: "Unmatched Artist",
            avatarURL: nil,
            appleMusicURL: nil
        ))
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningFixturePlayer() }
        )

        await room.load(show: show)
        XCTAssertEqual(search.searchCount, 1)
        XCTAssertEqual(show.artists.first?.appleMusicArtistID, "unmatched-artist-id")
        XCTAssertFalse(room.shouldReloadCatalog(for: show), "An empty but completed first load must not restart on every tab activation")

        await room.authorize()
        XCTAssertEqual(search.searchCount, 1, "Authorization must not repeat matching for an already connected artist")
        XCTAssertEqual(show.artists.first?.appleMusicArtistID, "unmatched-artist-id")
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
    }

    func testForegroundReturnRefreshesDeniedMusicAccessAndReloadsCatalog() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .previewOnly)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let catalog = AuthorizationTransitionCatalog(status: .denied)
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        XCTAssertEqual(room.access.authorizationStatus, .denied)
        XCTAssertEqual(catalog.fullFetchCount, 0)

        room.setForeground(false)
        catalog.setStatusForTesting(.authorized)
        room.setForeground(true)
        await room.refreshMusicAccessAfterForeground()

        XCTAssertEqual(room.access.authorizationStatus, .authorized)
        XCTAssertEqual(room.access.catalogPlaybackAccess, .available)
        XCTAssertEqual(catalog.fullFetchCount, 0, "granting access in Settings must not eagerly fetch full artist catalogs in the all-artists scope")
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
    }

    func testForegroundRevocationEndsFullPlaybackButKeepsLoadedTrackForPreviewFallback() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .previewOnly)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let catalog = AuthorizationTransitionCatalog(
            status: .authorized,
            playbackAccess: .available
        )
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.contains { $0.previewURL != nil } })
        room.restoreDisc(disc)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        let selectedTrackID = try XCTUnwrap(room.track?.id)
        let selectedIndex = room.trackIndex
        XCTAssertEqual(room.display.player.source, .fullCatalog)

        catalog.setStatusForTesting(.denied)
        await room.refreshMusicAccessAfterForeground()

        XCTAssertEqual(room.access.authorizationStatus, .denied)
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.track?.id, selectedTrackID)
        XCTAssertEqual(room.trackIndex, selectedIndex)
        XCTAssertEqual(room.elapsed, 0)
        XCTAssertEqual(room.display.roomMode, .preview)

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.track?.id, selectedTrackID)
        XCTAssertEqual(room.display.player.source, .preview)
    }

    func testForegroundAccountLimitEndsPausedFullPlaybackWithoutResettingTrack() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .previewOnly)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let catalog = AuthorizationTransitionCatalog(
            status: .authorized,
            playbackAccess: .available
        )
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.contains { $0.previewURL != nil } })
        room.restoreDisc(disc)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.playPause()
        XCTAssertEqual(room.display.player.phase, .paused)
        room.seek(42)

        let selectedTrackID = try XCTUnwrap(room.track?.id)
        let selectedIndex = room.trackIndex
        catalog.setPlaybackAccessForTesting(.accountLimited)
        await room.refreshMusicAccessAfterForeground()

        XCTAssertEqual(room.access.catalogPlaybackAccess, .accountLimited)
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .stopped)
        XCTAssertEqual(room.track?.id, selectedTrackID)
        XCTAssertEqual(room.trackIndex, selectedIndex)
        XCTAssertEqual(room.elapsed, 42, "capability loss must retain the paused playback position")
    }

    func testForegroundAccessCheckFailureKeepsEstablishedFullPlaybackAndWarnsForFuturePlayback() async throws {
        for scenario: ListeningFixtureScenario in [.singleFull, .previewOnly] {
            let fixture = try ListeningDebugFixtures(scenario: scenario)
            let context = fixture.container.mainContext
            let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
            let catalog = AuthorizationTransitionCatalog(
                status: .authorized,
                playbackAccess: .available
            )
            var playbackServices: [ListeningFixturePlayer] = []
            let room = ListeningRoomCoordinator(
                context: context,
                catalogService: catalog,
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { _ in
                    let service = ListeningFixturePlayer()
                    playbackServices.append(service)
                    return service
                }
            )
            defer {
                room.stop()
                room.mechanism.motion.stop()
            }

            await room.load(show: show)
            let disc = try XCTUnwrap(room.discs.first { !$0.tracks.isEmpty })
            room.restoreDisc(disc)
            room.playPause()
            try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
            XCTAssertEqual(room.display.player.source, .fullCatalog)

            catalog.setPlaybackAccessForTesting(.accessCheckFailed)
            await room.refreshMusicAccessAfterForeground()

            XCTAssertTrue(room.isPlaying)
            XCTAssertEqual(room.access.catalogPlaybackAccess, .accessCheckFailed)
            XCTAssertEqual(room.display.player.source, .fullCatalog)
            XCTAssertEqual(room.display.roomMode, .fullPlayback)
            XCTAssertEqual(room.display.headerNotice?.recoveryAction, .retryAccess)
            XCTAssertEqual(
                room.display.headerNotice?.message,
                ListeningCopy.text("暂时无法确认之后的完整播放权限。")
            )

            room.playPause()
            room.seek(42)
            XCTAssertEqual(room.display.player.phase, .paused)
            XCTAssertEqual(room.display.player.playPauseAction, .play)
            room.playPause()
            await room.settlePendingOperation()
            XCTAssertTrue(room.isPlaying, "temporary access uncertainty must allow the established session to resume")
            XCTAssertEqual(room.display.player.source, .fullCatalog)
            XCTAssertEqual(room.elapsed, 42, accuracy: 0.5)
            XCTAssertEqual(playbackServices.count, 1)

            guard disc.tracks.count > 2 else {
                XCTFail("fixture must provide at least three album tracks")
                continue
            }
            let nextTrack = disc.tracks[1]
            if scenario == .singleFull {
                XCTAssertNil(nextTrack.previewURL, "regression must cover a target with no preview fallback")
            }
            XCTAssertEqual(
                room.trackPresentation(for: nextTrack).capability,
                .fullPlayback,
                "tracks on the loaded disc should inherit the established full-catalog session while access is inconclusive"
            )

            room.skip(1)
            await room.settlePendingOperation()

            XCTAssertEqual(room.track?.id, nextTrack.id)
            XCTAssertTrue(room.isPlaying)
            XCTAssertTrue(room.wantsPlayback)
            XCTAssertEqual(room.display.player.source, .fullCatalog)
            XCTAssertTrue(room.display.player.shouldRotateDisc)
            XCTAssertEqual(
                playbackServices.count,
                1,
                "same-disc skip must reuse the established full-catalog transport instead of rebuilding or downgrading"
            )

            let selectedTrack = disc.tracks[2]
            room.loadDisc(disc, songID: selectedTrack.id)
            await room.settlePendingOperation()

            XCTAssertEqual(room.track?.id, selectedTrack.id)
            XCTAssertTrue(room.isPlaying)
            XCTAssertEqual(room.display.player.source, .fullCatalog)
            XCTAssertEqual(
                playbackServices.count,
                1,
                "explicit same-disc selection must also stay on the established transport"
            )
        }
    }

    func testForegroundRevocationDoesNotInterruptRunningPreview() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .previewOnly)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let catalog = AuthorizationTransitionCatalog(
            status: .authorized,
            playbackAccess: .accountLimited
        )
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.contains { $0.previewURL != nil } })
        room.restoreDisc(disc)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.display.player.source, .preview)

        catalog.setStatusForTesting(.denied)
        await room.refreshMusicAccessAfterForeground()

        XCTAssertEqual(room.access.authorizationStatus, .denied)
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.source, .preview)
        XCTAssertEqual(room.display.roomMode, .preview)
    }

    func testNewerSheetRetryWinsWhenForegroundAccessQueryCompletesLater() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let catalog = OutOfOrderMusicAccessCatalog()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            catalog.resumeAll(
                with: .init(
                    authorizationStatus: .authorized,
                    catalogPlaybackAccess: .available
                )
            )
            room.stop()
            room.mechanism.motion.stop()
        }

        let foregroundRefresh = Task { await room.refreshMusicAccessAfterForeground() }
        try await waitForAccessRequestCount(1, catalog: catalog)
        let foregroundRequestID = try XCTUnwrap(catalog.pendingRequestIDs.first)

        let sheetRetry = Task { await room.refreshMusicAccess() }
        try await waitForAccessRequestCount(2, catalog: catalog)
        let retryRequestID = try XCTUnwrap(
            catalog.pendingRequestIDs.first(where: { $0 != foregroundRequestID })
        )

        catalog.resume(
            requestID: retryRequestID,
            with: .init(
                authorizationStatus: .authorized,
                catalogPlaybackAccess: .available
            )
        )
        await sheetRetry.value

        XCTAssertEqual(room.access.catalogPlaybackAccess, .available)
        XCTAssertTrue(room.accessResolved)

        catalog.resume(
            requestID: foregroundRequestID,
            with: .init(
                authorizationStatus: .authorized,
                catalogPlaybackAccess: .accountLimited
            )
        )
        await foregroundRefresh.value

        XCTAssertEqual(
            room.access.catalogPlaybackAccess,
            .available,
            "an older foreground query must not overwrite the newer sheet retry result"
        )
    }

    func testForegroundRefreshResolvingSameProvisionalAccessUnblocksSupersededInitialLoad() async throws {
        let (container, show) = try ListenTestData.make()
        let catalog = OutOfOrderMusicAccessCatalog()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            catalog.resumeAll(
                with: .init(
                    authorizationStatus: .authorized,
                    catalogPlaybackAccess: .accountLimited
                )
            )
            room.stop()
            room.mechanism.motion.stop()
        }

        let initialLoad = Task { await room.load(show: show) }
        try await waitForAccessRequestCount(1, catalog: catalog)
        let loadRequestID = try XCTUnwrap(catalog.pendingRequestIDs.first)

        XCTAssertEqual(room.access.authorizationStatus, .authorized)
        XCTAssertEqual(room.access.catalogPlaybackAccess, .accountLimited)
        XCTAssertFalse(room.accessResolved)
        XCTAssertEqual(room.display.roomMode, .connecting)

        let foregroundRefresh = Task { await room.refreshMusicAccessAfterForeground() }
        try await waitForAccessRequestCount(2, catalog: catalog)
        let foregroundRequestID = try XCTUnwrap(
            catalog.pendingRequestIDs.first(where: { $0 != loadRequestID })
        )

        catalog.resume(
            requestID: foregroundRequestID,
            with: .init(
                authorizationStatus: .authorized,
                catalogPlaybackAccess: .accountLimited
            )
        )
        await foregroundRefresh.value

        XCTAssertTrue(
            room.accessResolved,
            "the winning foreground query must resolve access even when it equals the provisional value"
        )

        catalog.resume(
            requestID: loadRequestID,
            with: .init(
                authorizationStatus: .authorized,
                catalogPlaybackAccess: .available
            )
        )
        await initialLoad.value

        XCTAssertEqual(
            room.access.catalogPlaybackAccess,
            .accountLimited,
            "the older initial-load query must remain superseded"
        )
        XCTAssertTrue(room.accessResolved)
        XCTAssertNotEqual(
            room.display.roomMode,
            .connecting,
            "a completed load must not remain permanently stuck in the connecting presentation"
        )
        XCTAssertFalse(
            room.shouldReloadCatalog(for: show),
            "the regression must cover the completed-key state that would otherwise preserve the stuck room"
        )
    }

    func testSuccessfulAccessRetryKeepsPreviewModeWhilePreviewTransportIsRunning() async throws {
        let fixture = try ListeningDebugFixtures(scenario: .previewOnly)
        let context = fixture.container.mainContext
        let show = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        let catalog = AuthorizationTransitionCatalog(
            status: .authorized,
            playbackAccess: .accessCheckFailed
        )
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.contains { $0.previewURL != nil } })
        room.restoreDisc(disc)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        XCTAssertEqual(room.display.player.source, .preview)
        XCTAssertEqual(room.display.roomMode, .preview)

        catalog.setPlaybackAccessForTesting(.available)
        await room.refreshMusicAccess()

        XCTAssertEqual(room.access.catalogPlaybackAccess, .available)
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.source, .preview)
        XCTAssertEqual(
            room.display.roomMode,
            .preview,
            "the header must describe the still-running preview transport until it is replaced"
        )

        room.stop()
        XCTAssertEqual(room.display.roomMode, .fullPlayback)
    }

    private func waitForAccessRequestCount(
        _ count: Int,
        catalog: OutOfOrderMusicAccessCatalog
    ) async throws {
        for _ in 0..<200 {
            if catalog.pendingRequestIDs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(count) Music access requests")
    }

    func testImportedArtistAutoMatchRequiresOneExactIdentity() {
        let exact = RecognizedArtist(id: "1", canonicalName: "Beyoncé", avatarURL: nil, appleMusicURL: nil)
        let fuzzy = RecognizedArtist(id: "2", canonicalName: "Beyoncé Live", avatarURL: nil, appleMusicURL: nil)
        XCTAssertEqual(
            ArtistNameMatching.uniqueExactMatch(for: "  Beyonce ", among: [fuzzy, exact])?.id,
            "1"
        )

        let collision = RecognizedArtist(id: "3", canonicalName: "Beyonce", avatarURL: nil, appleMusicURL: nil)
        XCTAssertNil(
            ArtistNameMatching.uniqueExactMatch(for: "Beyoncé", among: [exact, collision]),
            "Same-name collisions must remain unresolved for manual confirmation"
        )
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
        XCTAssertEqual(room.browser.scope, .artist("new"))
        XCTAssertEqual(room.browsingArtist?.name, "New Artist")
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
        XCTAssertEqual(room.discs.first?.tracks.map(\.id), ["a2"])
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


@MainActor
final class ListeningDiscDetailTapPolicyTests: XCTestCase {
    func testDetailTapRequiresStableSeatedDisc() {
        XCTAssertTrue(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .removed,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: true,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: false,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: true
            )
        )
    }

    func testDetailTapUsesEightPointMovementLimitAndProjectedDiscEllipse() {
        XCTAssertTrue(ListeningDiscDetailTapPolicy.isIntentionalTap(CGSize(width: 6, height: 5)))
        XCTAssertFalse(ListeningDiscDetailTapPolicy.isIntentionalTap(CGSize(width: 8, height: 1)))

        let center = CGPoint(x: 100, y: 80)
        let size = CGSize(width: 120, height: 60)
        XCTAssertTrue(ListeningDiscDetailTapPolicy.contains(center, center: center, size: size))
        XCTAssertTrue(
            ListeningDiscDetailTapPolicy.contains(
                CGPoint(x: 167, y: 80),
                center: center,
                size: size
            ),
            "The CD hit area should include the agreed eight-point tolerance"
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.contains(
                CGPoint(x: 169, y: 80),
                center: center,
                size: size
            )
        )
    }
}
