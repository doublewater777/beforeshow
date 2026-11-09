import XCTest
@testable import BeforeShow

/// 足迹里的数字唱片插播一首后，放回原来那张。
@MainActor
final class ListeningCutInTests: XCTestCase {
    private func disc(_ id: String) -> ListeningDisc {
        ListeningDisc(id: id, title: id, artworkURL: nil, tracks: [])
    }

    func testRemembersTheRecordItReplaces() {
        let seated = ListeningCutIn.remembering(
            nil, cutIn: "footprint-number-7", loadedDisc: disc("album"),
            songID: "song-3", time: 42, wasPlaying: true
        )
        XCTAssertEqual(seated?.disc.id, "album")
        XCTAssertEqual(seated?.songID, "song-3")
        XCTAssertEqual(seated?.time, 42)
        XCTAssertEqual(seated?.wasPlaying, true)
        XCTAssertEqual(seated?.cutInDiscID, "footprint-number-7")
    }

    func testASecondCutInStillReturnsToTheOriginalRecord() {
        let first = ListeningCutIn.remembering(
            nil, cutIn: "footprint-number-7", loadedDisc: disc("album"),
            songID: "song-3", time: 42, wasPlaying: true
        )
        let second = ListeningCutIn.remembering(
            first, cutIn: "footprint-number-8", loadedDisc: disc("footprint-number-7"),
            songID: "n7", time: 10, wasPlaying: true
        )
        XCTAssertEqual(second?.disc.id, "album")
        XCTAssertEqual(second?.time, 42)
        XCTAssertEqual(second?.cutInDiscID, "footprint-number-8")
    }

    func testNothingToReturnToWhenTheDeckIsEmpty() {
        XCTAssertNil(ListeningCutIn.remembering(
            nil, cutIn: "footprint-number-7", loadedDisc: nil, songID: nil, time: 0, wasPlaying: false
        ))
    }
}
