import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningRoomLifecycleTests: XCTestCase {
    func testFullBackgroundAndTabPauseRespectUserPause() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.setForeground(false)
        XCTAssertTrue(room.isPlaying)
        room.setActive(false)
        XCTAssertFalse(room.isPlaying)
        room.setForeground(true); room.setActive(true)
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { !room.isPlaying && !room.busy }
        room.setActive(false); room.setActive(true)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(room.isPlaying)
        room.stop(); room.mechanism.motion.stop()
    }
    func testCurrentShowChangeClearsOldCardEvenWhenNewShowHasNoArtist() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        let other = try Show(name: "Other", date: Date().addingTimeInterval(10000), startTime: Date().addingTimeInterval(10000))
        container.mainContext.insert(other); try container.mainContext.save()
        await room.load(show: other)
        XCTAssertNil(room.track)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertTrue(room.discs.isEmpty)
        XCTAssertEqual(room.show?.id, other.id)
        XCTAssertFalse(room.isPlaying)
        try await ListenTestData.settle(room) { !room.busy }
        room.mechanism.motion.stop()
    }
}
