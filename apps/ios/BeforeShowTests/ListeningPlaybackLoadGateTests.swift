import XCTest
@testable import BeforeShow

final class ListeningPlaybackLoadGateTests: XCTestCase {
    func testOnlyTheLatestLoadMayWriteTheSharedPlayer() {
        XCTAssertTrue(ListeningPlaybackLoadGate.canWrite(generation: 4, latest: 4))
        XCTAssertFalse(ListeningPlaybackLoadGate.canWrite(generation: 3, latest: 4))
        XCTAssertFalse(ListeningPlaybackLoadGate.canWrite(generation: 5, latest: 4))
    }
}
