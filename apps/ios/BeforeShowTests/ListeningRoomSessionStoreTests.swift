import XCTest
@testable import BeforeShow

@MainActor
final class ListeningRoomSessionStoreTests: XCTestCase {
    override func tearDown() {
        ListeningRoomSessionStore.shared.adopt(nil)
        super.tearDown()
    }

    func testPendingArtistMatchRequestIsScopedAndNotDroppedForAnotherShow() {
        let session = ListeningRoomSessionStore.shared
        let showID = UUID()
        session.requestArtistMatch(showID: showID, slotIndex: 2, resumePlaybackOnSuccess: true)

        XCTAssertEqual(session.pendingArtistMatchRequest?.showID, showID)
        XCTAssertEqual(session.pendingArtistMatchRequest?.slotIndex, 2)
        XCTAssertTrue(session.pendingArtistMatchRequest?.resumePlaybackOnSuccess == true)
        XCTAssertNil(session.consumeArtistMatchRequest(for: UUID()))
        XCTAssertEqual(session.pendingArtistMatchRequest?.showID, showID)

        let consumed = session.consumeArtistMatchRequest(for: showID)
        XCTAssertEqual(consumed?.slotIndex, 2)
        XCTAssertTrue(consumed?.resumePlaybackOnSuccess == true)
        XCTAssertNil(session.pendingArtistMatchRequest)
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
    }
}
