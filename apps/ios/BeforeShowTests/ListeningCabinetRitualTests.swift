import XCTest
@testable import BeforeShow

@MainActor
final class ListeningCabinetRitualTests: XCTestCase {
    func testChangeDiscOpensImmediatelyWithoutMovingLidOrStoppingPlayback() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.mechanism.motion.stop() }
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.browseArtists.first?.albums.first))
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.openCabinet()
        XCTAssertTrue(room.cabinet.isPresented)
        XCTAssertTrue(room.mechanism.isClosed)
        XCTAssertTrue(room.isPlaying)
        room.cabinet.dismiss()
        room.completeCabinetSelection()
        XCTAssertFalse(room.cabinet.isPresented)
        XCTAssertTrue(room.isPlaying)
    }

    func testSelectionWaitsForDismissalThenLoadsUsingExistingPlaybackPath() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.mechanism.motion.stop() }
        await room.load(show: show)
        let disc = try XCTUnwrap(room.browseArtists.first?.albums.first)
        room.openCabinet()
        room.selectCabinetDisc(disc)
        XCTAssertFalse(room.cabinet.isPresented)
        await Task.yield()
        XCTAssertNil(room.mechanism.disc)
        room.completeCabinetSelection()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(room.track?.id, disc.tracks.first?.id)
        XCTAssertTrue(room.mechanism.isClosed)
        XCTAssertTrue(room.display.player.canPlayPause)
        XCTAssertTrue(room.mechanism.motion.spinning)
        room.playPause()
        XCTAssertFalse(room.isPlaying)
        XCTAssertFalse(room.mechanism.motion.spinning)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
    }

    func testReplacementUsesSelectedDiscAndSameDiscSelectionKeepsPlayback() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.mechanism.motion.stop() }
        await room.load(show: show)
        let album = try XCTUnwrap(room.browseArtists.first?.albums.first)
        let replacement = try XCTUnwrap(room.compilationDiscs.first)
        room.restoreDisc(album)
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.openCabinet()
        room.selectCabinetDisc(album)
        room.completeCabinetSelection()
        XCTAssertTrue(room.isPlaying)
        XCTAssertFalse(room.busy)
        room.openCabinet()
        room.selectCabinetDisc(replacement)
        room.completeCabinetSelection()
        try await ListenTestData.settle(room) { room.mechanism.disc?.id == replacement.id && room.isPlaying && !room.busy }
        XCTAssertEqual(room.track?.id, replacement.tracks.first?.id)
        XCTAssertTrue(room.mechanism.isClosed)
    }

    func testLeavingListenDuringDismissalCancelsSelection() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.mechanism.motion.stop() }
        await room.load(show: show)
        room.openCabinet()
        room.selectCabinetDisc(try XCTUnwrap(room.browseArtists.first?.albums.first))
        room.setActive(false)
        room.completeCabinetSelection()
        await Task.yield()
        XCTAssertNil(room.mechanism.disc)
        XCTAssertEqual(room.cabinet.phase, .idle)
    }

    func testReducedMotionLoadsAfterDismissalWithoutContinuousRotation() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        defer { room.mechanism.motion.stop() }
        await room.load(show: show)
        room.mechanism.motion.reducedMotion = true
        room.openCabinet()
        XCTAssertTrue(room.cabinet.isPresented)
        room.selectCabinetDisc(try XCTUnwrap(room.browseArtists.first?.albums.first))
        XCTAssertNil(room.mechanism.disc)
        room.completeCabinetSelection()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertTrue(room.mechanism.isClosed)
        let angle = room.mechanism.motion.discAngle
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(room.mechanism.motion.discAngle, angle)
    }
}
