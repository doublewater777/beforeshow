import XCTest
@testable import BeforeShow

final class TimetablePreviewSearchResponseTests: XCTestCase {
    func testLinkedIdentitySkipsArtistMetadataAndTracksWithoutPreview() throws {
        let response = try decode("""
        {"results":[
          {"wrapperType":"artist","artistId":123,"artistName":"Canonical Name"},
          {"kind":"song","trackId":1,"artistId":123,"artistName":"Canonical Name"},
          {"kind":"song","trackId":2,"artistId":456,"artistName":"Display Name","previewUrl":"https://example.com/wrong.m4a"},
          {"kind":"song","trackId":3,"artistId":123,"artistName":"Canonical Name","trackName":"Song","previewUrl":"https://example.com/right.m4a"}
        ]}
        """)
        let preview = try XCTUnwrap(response.preview(artistName: "Display Name", artistID: "123"))
        XCTAssertEqual(preview.songID, "3")
        XCTAssertEqual(preview.previewURL?.absoluteString, "https://example.com/right.m4a")
        XCTAssertEqual(preview.title, "Song")
        XCTAssertEqual(preview.artistName, "Canonical Name")
    }

    func testSearchDoesNotPreviewOtherArtist() throws {
        let response = try decode("""
        {"results":[
          {"kind":"song","trackId":1,"artistId":456,"artistName":"Other Artist","previewUrl":"https://example.com/wrong.m4a"},
          {"kind":"song","trackId":2,"artistId":123,"artistName":"Artist","previewUrl":"https://example.com/right.m4a"}
        ]}
        """)
        XCTAssertEqual(response.preview(artistName: "  ARTIST  ", artistID: nil)?.songID, "2")
        XCTAssertNil(response.preview(artistName: "Missing Artist", artistID: nil))
        XCTAssertNil(response.preview(artistName: "Other Artist", artistID: "999"))
    }

    func testUnlinkedSameNameIsNotEnoughToChooseBetweenIdentities() throws {
        let response = try decode("""
        {"results":[
          {"kind":"song","trackId":1,"artistId":123,"artistName":"Artist","previewUrl":"https://example.com/one.m4a"},
          {"kind":"song","trackId":2,"artistId":456,"artistName":"Artist","previewUrl":"https://example.com/two.m4a"}
        ]}
        """)
        XCTAssertNil(response.preview(artistName: "Artist", artistID: nil))
        XCTAssertEqual(response.preview(artistName: "Artist", artistID: "456")?.songID, "2")
    }

    func testMissingOrNonHTTPPreviewDoesNotProducePlayableItem() throws {
        for preview in ["null", "\"file:///tmp/not-a-preview.m4a\""] {
            let response = try decode("""
            {"results":[{"kind":"song","trackId":1,"artistId":123,"artistName":"Artist","previewUrl":\(preview)}]}
            """)
            XCTAssertNil(response.preview(artistName: "Artist", artistID: "123"))
        }
    }

    private func decode(_ json: String) throws -> TimetablePreviewSearchResponse {
        try JSONDecoder().decode(TimetablePreviewSearchResponse.self, from: Data(json.utf8))
    }
}

@MainActor
final class TimetablePreviewPlayerTests: XCTestCase {
    func testPlayerStateLifecycle() {
        let player = TimetablePreviewPlayer.shared
        player.stop()

        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertNil(player.activePerformanceID)
        XCTAssertNil(player.activeTrackTitle)
    }
}
