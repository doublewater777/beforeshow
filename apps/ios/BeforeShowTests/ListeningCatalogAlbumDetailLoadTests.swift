import XCTest
@testable import BeforeShow

final class ListeningCatalogAlbumDetailLoadTests: XCTestCase {
    func testCancellationAndTransportFailuresPropagate() {
        XCTAssertTrue(ListeningCatalogAlbumDetailLoad.propagate(CancellationError()) is CancellationError)
        let transport = URLError(.networkConnectionLost)
        XCTAssertEqual((ListeningCatalogAlbumDetailLoad.propagate(transport) as? URLError)?.code, .networkConnectionLost)
    }

    func testAnAlbumWithNoSongsIsStillACompleteRecord() {
        XCTAssertTrue(ListeningCatalogAlbumDetailLoad.accepts(songCount: 0))
        XCTAssertTrue(ListeningCatalogAlbumDetailLoad.accepts(songCount: 3))
    }
}
