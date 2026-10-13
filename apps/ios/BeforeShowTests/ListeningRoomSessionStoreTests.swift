import XCTest
@testable import BeforeShow

@MainActor
final class ListeningRoomSessionStoreTests: XCTestCase {
    override func tearDown() {
        ListeningRoomSessionStore.shared.room?.mechanism.motion.stop()
        ListeningRoomSessionStore.shared.adopt(nil)
        super.tearDown()
    }

    func testAdoptDoesNotPublishChrome() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )

        ListeningRoomSessionStore.shared.adopt(room)

        XCTAssertTrue(ListeningRoomSessionStore.shared.room === room)
        XCTAssertNil(ListeningRoomSessionStore.shared.chromeRoom)
        room.mechanism.motion.stop()
    }

    func testPublishChromeAdoptsAndExposesChromeRoom() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )

        ListeningRoomSessionStore.shared.publishChrome(room)

        XCTAssertTrue(ListeningRoomSessionStore.shared.room === room)
        XCTAssertTrue(ListeningRoomSessionStore.shared.chromeRoom === room)

        ListeningRoomSessionStore.shared.unpublishChrome()
        XCTAssertTrue(ListeningRoomSessionStore.shared.room === room)
        XCTAssertNil(ListeningRoomSessionStore.shared.chromeRoom)
        room.mechanism.motion.stop()
    }

    func testReplacingRoomUnpublishesChrome() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let first = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )
        let second = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            playbackFactory: { ListeningTestPlayer(source: $0) }
        )

        ListeningRoomSessionStore.shared.publishChrome(first)
        ListeningRoomSessionStore.shared.adopt(second)

        XCTAssertTrue(ListeningRoomSessionStore.shared.room === second)
        XCTAssertNil(ListeningRoomSessionStore.shared.chromeRoom)
        first.mechanism.motion.stop()
        second.mechanism.motion.stop()
    }
}
