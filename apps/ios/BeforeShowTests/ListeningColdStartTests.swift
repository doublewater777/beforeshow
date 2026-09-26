import XCTest
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningColdStartTests: XCTestCase {
    func testFirstSongsCanPlayWhileSlowArtistIsPending() async throws {
        let (container, show) = try makeShow()
        let catalog = ColdStartCatalog()
        let room = makeRoom(container, catalog: catalog)
        let load = Task { await room.load(show: show) }
        defer {
            load.cancel()
            catalog.gate.release()
            room.stop()
            room.mechanism.motion.stop()
        }

        try await wait { catalog.started.count == 7 && !room.compilationDiscs.isEmpty }
        XCTAssertFalse(catalog.gate.isReleased)
        XCTAssertLessThanOrEqual(catalog.peakConcurrentRequests, 4)
        XCTAssertFalse(room.compilationDiscs.flatMap(\.tracks).contains { $0.id == "song-0" })
        let disc = try XCTUnwrap(room.compilationDiscs.first)
        room.loadPlayableDisc(disc)
        try await ListenTestData.settle(room) { room.isPlaying }
        XCTAssertTrue(room.isPlaying, "A slow first artist must not block listening to other artists")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CatalogSong>()), 0)

        catalog.gate.release()
        await load.value
        XCTAssertEqual(Set(room.compilationDiscs.flatMap(\.tracks).map(\.id)), Set((0..<7).map { "song-\($0)" }))
        XCTAssertEqual(room.mechanism.disc?.id, disc.id, "Enrichment must not replace the playing CD")
        XCTAssertTrue(room.isPlaying)
    }

    func testLateRuntimeResponseCannotRepopulateAnotherShow() async throws {
        let (container, show) = try makeShow()
        let catalog = ColdStartCatalog()
        let room = makeRoom(container, catalog: catalog)
        let load = Task { await room.load(show: show) }
        defer {
            load.cancel()
            catalog.gate.release()
            room.stop()
            room.mechanism.motion.stop()
        }
        try await wait { catalog.started.count == 7 && !room.compilationDiscs.isEmpty }
        let next = try Show(name: "Next", date: .now, startTime: .now)
        container.mainContext.insert(next)
        try container.mainContext.save()
        await room.load(show: next)
        catalog.gate.release()
        await load.value
        XCTAssertEqual(room.show?.id, next.id)
        XCTAssertTrue(room.discs.isEmpty)
    }

    func testCancelledRuntimeResponseIsNotPublished() async throws {
        let (container, show) = try makeShow()
        let catalog = ColdStartCatalog()
        let room = makeRoom(container, catalog: catalog)
        let load = Task { await room.load(show: show) }
        defer { room.stop(); room.mechanism.motion.stop() }
        do {
            try await wait { catalog.started.count == 7 && !room.compilationDiscs.isEmpty }
        } catch {
            load.cancel()
            catalog.gate.release()
            throw error
        }
        let ids = room.compilationDiscs.flatMap(\.tracks).map(\.id)
        load.cancel()
        catalog.gate.release()
        await load.value
        XCTAssertEqual(room.compilationDiscs.flatMap(\.tracks).map(\.id), ids)
        XCTAssertFalse(room.isCatalogEnriching)
    }

    func testArtistMatchingUsesBoundedConcurrencyAndPreservesSlotIdentity() async throws {
        let search = ColdStartSearch()
        let slots = (0..<7).map { ArtistSlot(name: "Artist \($0)", avatarURL: nil) }
        let matching = Task { try await ListeningArtistAutoMatcher(search: search).matches(for: slots) }
        defer { matching.cancel(); search.gate.release() }
        try await wait { search.requests.started.count == 7 }
        XCTAssertFalse(search.gate.isReleased)
        XCTAssertLessThanOrEqual(search.requests.peakConcurrentRequests, 4)
        search.gate.release()
        let result = try await matching.value
        XCTAssertEqual(result.count, slots.count)
        for index in slots.indices { XCTAssertEqual(result[index]?.canonicalName, slots[index].name) }
    }

    private func makeShow() throws -> (ModelContainer, Show) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let show = try Show(name: "Festival", date: .now.addingTimeInterval(10000), startTime: .now.addingTimeInterval(10000))
        show.artists = (0..<7).map { ArtistSlot(name: "Artist \($0)", avatarURL: nil, appleMusicArtistID: String($0)) }
        container.mainContext.insert(show)
        try container.mainContext.save()
        return (container, show)
    }

    private func makeRoom(_ container: ModelContainer, catalog: ColdStartCatalog) -> ListeningRoomCoordinator {
        ListeningRoomCoordinator(context: container.mainContext, catalogService: catalog,
                                 artistSearchService: ListeningFixtureArtistSearch(),
                                 playbackFactory: { _ in ListeningFixturePlayer() })
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ColdStartTestError.timedOut
    }
}

private enum ColdStartTestError: Error { case timedOut }

private final class ColdStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var isReleased: Bool { lock.withLock { released } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if released { return true }
                waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock {
            released = true
            defer { waiters.removeAll() }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

private final class ColdStartRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    private var active = 0
    private var peak = 0
    var started: [String] { lock.withLock { ids } }
    var peakConcurrentRequests: Int { lock.withLock { peak } }
    func begin(_ id: String) { lock.withLock { ids.append(id); active += 1; peak = max(peak, active) } }
    func end() { lock.withLock { active -= 1 } }
}

private final class ColdStartCatalog: ListeningMusicCatalogServicing, Sendable {
    let gate = ColdStartGate()
    let requests = ColdStartRequests()
    var started: [String] { requests.started }
    var peakConcurrentRequests: Int { requests.peakConcurrentRequests }
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { .init(authorizationStatus: .authorized, canPlayCatalogContent: true) }
    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        requests.begin(artistID)
        defer { requests.end() }
        if artistID == "0" { await gate.wait() }
        return [.init(songID: "song-\(artistID)", title: "Song", artistName: artistID,
                      albumID: nil, albumTitle: nil, artworkURL: nil, duration: 180,
                      performerArtistIDs: [artistID], performerArtistNames: [artistID], previewURL: nil)]
    }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.incompleteCatalog(artistID)
    }
}

private final class ColdStartSearch: ArtistSearchServicing, Sendable {
    let gate = ColdStartGate()
    let requests = ColdStartRequests()
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        requests.begin(query)
        defer { requests.end() }
        if query == "Artist 0" { await gate.wait() }
        return [.init(id: query, canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
    }
}
