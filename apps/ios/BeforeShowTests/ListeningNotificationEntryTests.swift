import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningNotificationEntryTests: XCTestCase {
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
            defer { room.stop(); room.stopHardwareMotion() }
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
            XCTAssertEqual(room.mechanism.disc?.id, "album")
            XCTAssertEqual(player.loadedSongIDs, previewIDs)
            XCTAssertNil(room.browser.detail)
            XCTAssertEqual(catalog.authorizationRequests, 0)
        }
    }
    func testResumingTheSameSongOnANewDayRefreshesTheShowsLastListeningTime() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop(); room.stopHardwareMotion() }
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first { $0.id == "album" }))
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.playPause()
        let recent = try XCTUnwrap(room.recentListening)
        let yesterday = Date().addingTimeInterval(-172800)
        recent.playedAt = yesterday
        try container.mainContext.save()
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        XCTAssertTrue(show.timingCalendar().isDate(recent.playedAt, inSameDayAs: Date()))
    }

    func testMissingDiscsFallBackToTheArtistAndLegacyPayloadsStillOpenTheRoom() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.stop(); room.stopHardwareMotion() }
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
        defer { room.stop(); room.stopHardwareMotion() }
        await room.load(show: show)
        room.loadDisc(try XCTUnwrap(room.compilationDiscs.first), autoplay: false)
        await Task.yield()
        XCTAssertTrue(room.busy)
        let play = try XCTUnwrap(NotificationDeepLink(userInfo: [
            "showID": show.id.uuidString, "destination": "listen", "discID": "album"
        ], actionIdentifier: "playListeningDisc"))
        let entry = Task { await ListeningNotificationEntry.open(play, show: show, room: room) }
        defer { entry.cancel() }
        try await ListenTestData.settle(room) { room.isPlaying && room.mechanism.disc?.id == "album" }
        await entry.value
        XCTAssertEqual(room.mechanism.disc?.id, "album")
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
            defer { room.stop(); room.stopHardwareMotion() }
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
        defer { room.stop(); room.stopHardwareMotion() }
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
