import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningRoomLifecycleTests: XCTestCase {
    func testFullBackgroundAndTabHideNeverOwnTransport() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first))
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.setForeground(false)
        XCTAssertTrue(room.isPlaying)
        room.setActive(false)
        XCTAssertTrue(room.isPlaying)
        room.setForeground(true); room.setActive(true)
        XCTAssertTrue(room.isPlaying)
        room.playPause()
        try await ListenTestData.settle(room) { !room.isPlaying && !room.busy }
        room.setActive(false); room.setActive(true)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(room.isPlaying)
        room.stop(); room.mechanism.motion.stop()
    }

    func testLoadedDiscRestoresAcrossCoordinatorRecreationWithoutAutoplay() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        room.restoreDisc(disc, songID: songID)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertEqual(reopened.playbackState, .idle)
        XCTAssertFalse(reopened.isPlaying)

        await reopened.load(show: show)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertFalse(reopened.isPlaying)
        reopened.mechanism.motion.stop()
    }

    func testCurrentShowChangeKeepsLoadedDiscEvenWhenNewShowHasNoArtist() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        room.restoreDisc(disc, songID: songID)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        let other = try Show(name: "Other", date: Date().addingTimeInterval(10000), startTime: Date().addingTimeInterval(10000))
        container.mainContext.insert(other); try container.mainContext.save()
        await room.load(show: other)
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertTrue(room.discs.isEmpty)
        XCTAssertEqual(room.show?.id, other.id)
        XCTAssertFalse(room.isPlaying)
        try await ListenTestData.settle(room) { !room.busy }
        room.mechanism.motion.stop()
    }

    func testReturningDiscToCabinetClearsColdLaunchState() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first))
        try await room.mechanism.unload()

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertFalse(reopened.mechanism.hasDisc)
        XCTAssertNil(reopened.mechanism.disc)
        XCTAssertNil(reopened.track)
        reopened.mechanism.motion.stop()
    }

    func testSameShowArtistChangeRequiresCatalogReload() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertFalse(room.browseArtists.contains { $0.id == "d" })

        show.artists.append(ArtistSlot(name: "D", avatarURL: nil, appleMusicArtistID: "d"))
        container.mainContext.insert(ArtistCatalogSnapshot(artistID: "d", artistName: "D", orderedSongIDs: ["a1"]))
        try container.mainContext.save()

        XCTAssertTrue(room.shouldReloadCatalog(for: show))
        await room.load(show: show)
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertTrue(room.browseArtists.contains { $0.id == "d" })
        room.mechanism.motion.stop()
    }

    func testFailedPlaybackRetryRebuildsTransport() async throws {
        let (container, show) = try ListenTestData.make()
        var services: [RetryPlaybackService] = []
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in
                let service = RetryPlaybackService()
                services.append(service)
                return service
            }
        )
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        room.restoreDisc(disc)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(services.count, 1)
        services[0].failure = .songUnavailable(try XCTUnwrap(room.track?.id))
        room.tick()
        XCTAssertEqual(room.playbackState, .failed)
        XCTAssertNotNil(room.playbackError)
        services[0].failure = nil
        room.retryCurrentPlayback()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[1].prepareCount, 1)
        room.stop(); room.mechanism.motion.stop()
    }
}

@MainActor
private final class RetryPlaybackService: ListeningPlaybackServicing {
    var failure: ListeningPlaybackError?
    private(set) var prepareCount = 0
    private let player = ListeningFixturePlayer()
    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        prepareCount += 1
        try await player.prepare(items: items, source: source, startingAtSongID: startingAtSongID)
    }
    func play() async throws { try await player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
    func seek(to time: TimeInterval) { player.seek(to: time) }
    func skipToNext() async throws { try await player.skipToNext() }
    func skipToPrevious() async throws { try await player.skipToPrevious() }
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? { player.snapshot(observedAt: observedAt) }
}
