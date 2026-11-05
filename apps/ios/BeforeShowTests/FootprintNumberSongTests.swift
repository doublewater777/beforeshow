import XCTest
@testable import BeforeShow

final class FootprintNumberSongTests: XCTestCase {
    func testEveryCountFromOneToFiftyHasARecord() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 7), FootprintNumberSong(number: 7, title: "七里香", artist: "周杰伦", trackID: 536115195))
        XCTAssertEqual(FootprintNumberSongs.song(for: 36)?.title, "36 Degrees")
        XCTAssertTrue((1...50).allSatisfy { FootprintNumberSongs.song(for: $0) != nil })
        XCTAssertEqual(Set((1...50).compactMap { FootprintNumberSongs.song(for: $0)?.trackID }).count, 50, "no two records share a track")
        XCTAssertNil(FootprintNumberSongs.song(for: 0))
        XCTAssertNil(FootprintNumberSongs.song(for: 51))
    }

    func testShelfShowsUnlockedNewestFirstAndTheNextSealedRecord() {
        let shelf = FootprintNumberSongs.shelf(showCount: 36)

        XCTAssertEqual(shelf.unlocked.first?.number, 36)
        XCTAssertEqual(shelf.unlocked.last?.number, 1)
        XCTAssertEqual(shelf.unlocked.count, 36)
        XCTAssertEqual(shelf.next?.number, 37, "every new show unlocks the next record")
        XCTAssertEqual(shelf.remaining, 1)
        XCTAssertEqual(shelf.total, 50)

        let fresh = FootprintNumberSongs.shelf(showCount: 0)
        XCTAssertTrue(fresh.unlocked.isEmpty)
        XCTAssertEqual(fresh.next?.number, 1)
        XCTAssertEqual(fresh.remaining, 1)
    }

    func testStoreResultBecomesAPreviewWithLargeCoverAndDetails() throws {
        var result = SongPreviewLookup.Result(trackId: 961067971, trackName: "36 Degrees", artistName: "Placebo")
        result.collectionName = "Placebo"
        result.releaseDate = "1996-06-17T07:00:00Z"
        result.primaryGenreName = "Alternative"
        result.trackTimeMillis = 214_000
        result.previewUrl = "https://example.invalid/36.m4a"
        result.artworkUrl100 = "https://example.invalid/art/100x100bb.jpg"

        let preview = try XCTUnwrap(SongPreviewLookup.preview(from: result))

        XCTAssertEqual(preview.album, "Placebo")
        XCTAssertEqual(preview.releaseYear, 1996)
        XCTAssertEqual(preview.genre, "Alternative")
        XCTAssertEqual(preview.duration, 214)
        XCTAssertEqual(preview.artworkURL?.absoluteString, "https://example.invalid/art/600x600bb.jpg")
    }

    func testAResultWithoutAPreviewIsLeftOut() {
        XCTAssertNil(SongPreviewLookup.preview(from: SongPreviewLookup.Result(trackId: 1, trackName: "x", artistName: "y")))
    }
}
