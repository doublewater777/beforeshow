import XCTest
@testable import BeforeShow

@MainActor
final class CDSoundPlayerTests: XCTestCase {
    func testReadSoundOnlyRoutesFromDiscSeat() {
        XCTAssertEqual(CDSoundPlayer.audioCues(for: "seat"), ["seat", "read"])
        XCTAssertEqual(CDSoundPlayer.audioCues(for: "read"), [])
        XCTAssertEqual(CDSoundPlayer.audioCues(for: "button"), ["button"])
        XCTAssertEqual(CDSoundPlayer.audioCues(for: "close"), [])
    }
}
