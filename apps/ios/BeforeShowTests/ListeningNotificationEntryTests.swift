import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningNotificationEntryTests: XCTestCase {
    func testHomePlaybackRequestsUndeterminedMusicAuthorizationAndStartsCachedDisc() async throws {
        let (container, show) = try ListenTestData.make()
        let session = ListeningRoomSessionStore.shared
        session.clear(stoppingTransport: true)
        defer { session.clear(stoppingTransport: true) }

        let catalog = HomePlaybackCatalog(status: .notDetermined, requestResult: .authorized)
        let dependencies = ListeningWidgetPlaybackDependencies(
            catalogService: catalog,
            artistSearchService: HomePlaybackArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let result = await ListeningHomePlaybackCoordinator.start(
            show: show,
            context: container.mainContext,
            dependencies: dependencies
        )

        guard case .started = result else {
            return XCTFail("Expected home listening to start, got \(result)")
        }
        XCTAssertEqual(catalog.authorizationRequests, 1)
        XCTAssertTrue(session.room?.isPlaying == true)
        XCTAssertEqual(session.room?.show?.id, show.id)
    }

    func testHomePlaybackRequestsArtistMatchWhenNoPlayableDiscAndArtistIsUnmatched() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let start = Date().addingTimeInterval(10_000)
        let show = try Show(name: "Unmatched Show", date: start, startTime: start)
        show.artists = [ArtistSlot(name: "Unknown Artist", avatarURL: nil)]
        container.mainContext.insert(show)
        try container.mainContext.save()

        let session = ListeningRoomSessionStore.shared
        session.clear(stoppingTransport: true)
        defer { session.clear(stoppingTransport: true) }
        let catalog = HomePlaybackCatalog(status: .authorized, requestResult: .authorized)
        let dependencies = ListeningWidgetPlaybackDependencies(
            catalogService: catalog,
            artistSearchService: HomePlaybackArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let result = await ListeningHomePlaybackCoordinator.start(
            show: show,
            context: container.mainContext,
            dependencies: dependencies
        )

        guard case .needsArtistMatch(_, let slotIndex, let artistName, let unmatchedCount) = result else {
            return XCTFail("Expected an artist match request, got \(result)")
        }
        XCTAssertEqual(slotIndex, 0)
        XCTAssertEqual(artistName, "Unknown Artist")
        XCTAssertEqual(unmatchedCount, 1)
        XCTAssertEqual(catalog.authorizationRequests, 0)
        XCTAssertEqual(result.blockingCatalogFailure?.stage, "artist_identity")
        XCTAssertEqual(result.blockingCatalogFailure?.reason, "no_match")
        XCTAssertTrue(result.revealsListenTab)
    }
    func testHomePlaybackReturnsAuthorizationFailureAndRevealsListenTab() async throws {
        let (container, show) = try ListenTestData.make()
        let session = ListeningRoomSessionStore.shared
        session.clear(stoppingTransport: true)
        defer { session.clear(stoppingTransport: true) }

        let catalog = HomePlaybackCatalog(status: .notDetermined, requestResult: .denied)
        let dependencies = ListeningWidgetPlaybackDependencies(
            catalogService: catalog,
            artistSearchService: HomePlaybackArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let result = await ListeningHomePlaybackCoordinator.start(
            show: show,
            context: container.mainContext,
            dependencies: dependencies
        )

        guard case .authorizationDenied = result else {
            return XCTFail("Expected authorizationDenied, got \(result)")
        }
        XCTAssertEqual(catalog.authorizationRequests, 1)
        XCTAssertFalse(session.room?.wantsPlayback ?? false)
        XCTAssertNil(result.blockingCatalogFailure)
        XCTAssertTrue(result.revealsListenTab)
    }

    func testHomePlaybackEmptyCatalogRevealsListenTab() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let start = Date().addingTimeInterval(10_000)
        let show = try Show(name: "Empty Catalog Show", date: start, startTime: start)
        show.artists = []
        container.mainContext.insert(show)
        try container.mainContext.save()

        let session = ListeningRoomSessionStore.shared
        session.clear(stoppingTransport: true)
        defer { session.clear(stoppingTransport: true) }
        let catalog = HomePlaybackCatalog(status: .authorized, requestResult: .authorized)
        let dependencies = ListeningWidgetPlaybackDependencies(
            catalogService: catalog,
            artistSearchService: HomePlaybackArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let result = await ListeningHomePlaybackCoordinator.start(
            show: show,
            context: container.mainContext,
            dependencies: dependencies
        )

        guard case .noPlayableContent = result else {
            return XCTFail("Expected noPlayableContent, got \(result)")
        }
        XCTAssertNil(result.blockingCatalogFailure)
        XCTAssertTrue(result.revealsListenTab)
    }

    func testHomePlaybackDoesNotReportCatalogMatchFailureWhenAPartialLineupCanPlay() async throws {
        let (container, show) = try ListenTestData.make()
        let session = ListeningRoomSessionStore.shared
        session.clear(stoppingTransport: true)
        defer { session.clear(stoppingTransport: true) }

        let catalog = HomePlaybackCatalog(status: .authorized, requestResult: .authorized)
        let dependencies = ListeningWidgetPlaybackDependencies(
            catalogService: catalog,
            artistSearchService: HomePlaybackArtistSearch(),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let result = await ListeningHomePlaybackCoordinator.start(
            show: show,
            context: container.mainContext,
            dependencies: dependencies
        )

        guard case .started = result else {
            return XCTFail("Expected playback to start with a partial match, got \(result)")
        }
        XCTAssertNil(result.blockingCatalogFailure)
        XCTAssertFalse(result.revealsListenTab)
    }

    func testListeningPresentationStartLifecycleAndReentry() async {
        let presentation = CurrentShowListeningPresentation()
        let started = presentation.start {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(started)
        XCTAssertTrue(presentation.isStarting)
        XCTAssertFalse(presentation.start {})
        presentation.cancel()
        XCTAssertFalse(presentation.isStarting)
    }

    func testBodyOpensDetailsAndPlayActionStartsPreviewWithoutRequestingMusicAuthorization() async throws {

        for previewIDs in [["a2", "a1"], ["a1"]] {
            let (container, show) = try ListenTestData.make()
            show.artists = [show.artists[0]]
            for song in try container.mainContext.fetch(FetchDescriptor<CatalogSong>()) {
                song.previewURL = previewIDs.contains(song.appleMusicSongID) ? "https://example.com/\(song.appleMusicSongID).m4a" : nil
            }
            try container.mainContext.save()
            let catalog = NotificationEntryCatalog()
            let player = ListeningTestPlayer(source: .preview)
            let room = ListeningRoomCoordinator(context: container.mainContext, catalogService: catalog,
                artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { _ in player })
            defer { room.stop() }
            let payload: [AnyHashable: Any] = ["showID": show.id.uuidString, "destination": "listen", "discID": "album", "artistID": "a"]
            let body = try XCTUnwrap(NotificationDeepLink(userInfo: payload))
            await ListeningNotificationEntry.open(body, show: show, room: room)
            XCTAssertEqual(room.browser.detail?.id, "album")
            XCTAssertFalse(room.hasLoadedDisc)
            XCTAssertFalse(room.isPlaying)

            room.browser.detail = nil
            var roadPayload = payload
            roadPayload["destination"] = "route"
            let play = try XCTUnwrap(NotificationDeepLink(userInfo: roadPayload, actionIdentifier: "playListeningDisc"))
            XCTAssertEqual(play.destination, .listen)
            XCTAssertTrue(play.requestsPlayback)
            await ListeningNotificationEntry.open(play, show: show, room: room)
            try await ListenTestData.settle(room) { room.isPlaying }
            XCTAssertEqual(room.loadedDisc?.id, "album")
            XCTAssertEqual(player.loadedSongIDs, previewIDs)
            XCTAssertNil(room.browser.detail)
            XCTAssertEqual(catalog.authorizationRequests, 0)
        }
    }
    func testResumingTheSameSongOnANewDayRefreshesTheShowsLastListeningTime() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop() }
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first { $0.id == "album" }))
        // The player reports playing before the room hears about it, so wait for the record itself.
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && room.recentListening != nil }
        room.playPause()
        try await ListenTestData.settle(room) { !room.isPlaying }
        let recent = try XCTUnwrap(room.recentListening)
        recent.playedAt = Date().addingTimeInterval(-172800)
        try container.mainContext.save()
        room.playPause()
        let calendar = show.timingCalendar()
        try await ListenTestData.settle(room) { room.isPlaying && calendar.isDate(recent.playedAt, inSameDayAs: Date()) }
    }

    func testMissingDiscsFallBackToTheArtistAndLegacyPayloadsStillOpenTheRoom() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop() }
        let missing = try XCTUnwrap(NotificationDeepLink(userInfo: [
            "showID": show.id.uuidString, "destination": "listen", "discID": "removed", "artistID": "a"
        ]))
        await ListeningNotificationEntry.open(missing, show: show, room: room)
        XCTAssertEqual(room.browser.scope, .artist("a"))
        XCTAssertNil(room.browser.detail)
        XCTAssertFalse(room.hasLoadedDisc)
        let legacy = try XCTUnwrap(NotificationDeepLink(userInfo: ["showID": show.id.uuidString, "destination": "listen"]))
        await ListeningNotificationEntry.open(legacy, show: show, room: room)
        XCTAssertEqual(room.browser.scope, .all)
        XCTAssertNil(legacy.discID)
        XCTAssertFalse(legacy.requestsPlayback)
        XCTAssertFalse(room.isPlaying)
    }

    func testPlayWaitsForAnExistingDiscInsertionInsteadOfDroppingTheRequest() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop() }
        await room.load(show: show)
        room.loadDisc(try XCTUnwrap(room.compilationDiscs.first), autoplay: false)
        await Task.yield()
        let play = try XCTUnwrap(NotificationDeepLink(userInfo: [
            "showID": show.id.uuidString, "destination": "listen", "discID": "album"
        ], actionIdentifier: "playListeningDisc"))
        let entry = Task { await ListeningNotificationEntry.open(play, show: show, room: room) }
        defer { entry.cancel() }
        try await ListenTestData.settle(room) { room.isPlaying && room.loadedDisc?.id == "album" }
        await entry.value
        XCTAssertEqual(room.loadedDisc?.id, "album")
        XCTAssertTrue(room.isPlaying)
    }

    func testUncachedNotificationShowsTheRecommendedArtistsShelfWithoutAuthorization() async throws {
        for connected in [true, false] {
            let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
            let start = Date().addingTimeInterval(86400)
            let show = try Show(name: "明天的现场", date: start, startTime: start)
            show.artists = [ArtistSlot(name: "B", avatarURL: nil, appleMusicArtistID: connected ? "b" : nil)]
            container.mainContext.insert(show)
            try container.mainContext.save()
            let catalog = NotificationEntryCatalog()
            let room = ListeningRoomCoordinator(context: container.mainContext, catalogService: catalog,
                artistSearchService: NotificationEntryArtistSearch(), playbackFactory: { ListeningTestPlayer(source: $0) })
            defer { room.stop() }
            let link = try XCTUnwrap(NotificationDeepLink(userInfo: [
                "showID": show.id.uuidString, "destination": "listen", "artistID": connected ? "b" : "unconnected-0", "artistName": "B"
            ]))
            await ListeningNotificationEntry.open(link, show: show, room: room)
            XCTAssertTrue(room.showsRack)
            XCTAssertEqual(room.browsingArtist?.name, "B")
            XCTAssertTrue(room.rackGroups.contains { $0.scope == .artist("b") && $0.name == "B" })
            XCTAssertEqual(catalog.authorizationRequests, 0)
        }
    }

    func testAnArtistReplacedWhileEntryLoadsFallsBackToTheWholeShow() async throws {
        let (container, show) = try ListenTestData.make()
        show.artists = [ArtistSlot(name: "B", avatarURL: nil)]
        try container.mainContext.save()
        let search = GatedNotificationEntryArtistSearch()
        let room = ListeningRoomCoordinator(context: container.mainContext, catalogService: NotificationEntryCatalog(),
            artistSearchService: search, playbackFactory: { ListeningTestPlayer(source: $0) })
        defer { room.stop() }
        let link = try XCTUnwrap(NotificationDeepLink(userInfo: [
            "showID": show.id.uuidString, "destination": "listen", "artistID": "unconnected-0", "artistName": "B"
        ]))
        let entry = Task { await ListeningNotificationEntry.open(link, show: show, room: room) }
        defer { entry.cancel(); Task { await search.release() } }
        for _ in 0..<1000 {
            if await search.isWaiting { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let didStart = await search.isWaiting
        XCTAssertTrue(didStart)
        show.artists = [ArtistSlot(name: "C", avatarURL: nil)]
        try container.mainContext.save()
        await search.release()
        await entry.value
        XCTAssertEqual(room.browser.scope, .all)
    }

}

private final class NotificationEntryCatalog: ListeningMusicCatalogServicing, Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var requestCount = 0
    var authorizationRequests: Int { lock.withLock { requestCount } }
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .notDetermined }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        lock.withLock { requestCount += 1 }
        return .denied
    }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .notDetermined, canPlayCatalogContent: false)
    }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

private final class HomePlaybackCatalog: ListeningMusicCatalogServicing, Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storedStatus: ListeningMusicAuthorizationStatus
    private nonisolated(unsafe) var requestCount = 0
    private let requestResult: ListeningMusicAuthorizationStatus

    init(status: ListeningMusicAuthorizationStatus, requestResult: ListeningMusicAuthorizationStatus) {
        storedStatus = status
        self.requestResult = requestResult
    }

    var authorizationRequests: Int { lock.withLock { requestCount } }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        lock.withLock { storedStatus }
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        lock.withLock {
            requestCount += 1
            storedStatus = requestResult
            return storedStatus
        }
    }

    func currentAccess() async -> ListeningMusicAccess {
        let status = currentAuthorizationStatus()
        return .init(authorizationStatus: status, canPlayCatalogContent: status == .authorized)
    }

    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

private struct HomePlaybackArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] { [] }
}

private struct NotificationEntryArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        [RecognizedArtist(id: "b", canonicalName: "B", avatarURL: nil, appleMusicURL: nil)]
    }
}

private actor GatedNotificationEntryArtistSearch: ArtistSearchServicing {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        guard query == "B", !released else { return [] }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
        return []
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
