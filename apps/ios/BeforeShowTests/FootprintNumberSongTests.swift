import XCTest
@testable import BeforeShow

final class FootprintNumberSongTests: XCTestCase {
    func testEveryCountFromOneToFiftyHasARecord() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 7), FootprintNumberSong(number: 7, title: "七里香", artist: "周杰伦"))
        XCTAssertEqual(FootprintNumberSongs.song(for: 36)?.title, "36 Degrees")
        XCTAssertTrue((1...50).allSatisfy { FootprintNumberSongs.song(for: $0) != nil })
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

    func testPreviewMatchNeedsTheSameArtistAndPrefersTheExactTitle() {
        let cover = result(1, "Seven Nation Army", "Some Cover Band")
        let remaster = result(2, "Seven Nation Army (Remastered)", "The White Stripes")
        let original = result(3, "Seven Nation Army", "The White Stripes")
        let noPreview = result(4, "Seven Nation Army", "The White Stripes", preview: false)

        let match = SongPreviewLookup.bestMatch(in: [cover, noPreview, remaster, original], title: "Seven Nation Army", artist: "The White Stripes")
        XCTAssertEqual(match?.trackId, 3)

        let onlyRemaster = SongPreviewLookup.bestMatch(in: [cover, remaster], title: "Seven Nation Army", artist: "The White Stripes")
        XCTAssertEqual(onlyRemaster?.trackId, 2)

        XCTAssertNil(SongPreviewLookup.bestMatch(in: [cover], title: "Seven Nation Army", artist: "The White Stripes"))
    }

    func testPreviewMatchIgnoresCaseAndPunctuation() {
        let found = SongPreviewLookup.bestMatch(in: [result(5, "25 or 6 to 4 - 2002 Remaster", "Chicago")], title: "25 or 6 to 4", artist: "chicago")
        XCTAssertEqual(found?.trackId, 5)
    }

    func testPreviewMatchByTitleAloneWhenNoArtistIsGiven() {
        let found = SongPreviewLookup.bestMatch(in: [result(6, "Five Hundred Miles", "Peter, Paul and Mary")], title: "Five Hundred Miles", artist: "")
        XCTAssertEqual(found?.trackId, 6)
    }

    private func result(_ id: Int, _ title: String, _ artist: String, preview: Bool = true) -> SongPreviewLookup.Result {
        SongPreviewLookup.Result(
            trackId: id,
            trackName: title,
            artistName: artist,
            previewUrl: preview ? "https://example.invalid/\(id).m4a" : nil,
            artworkUrl100: nil,
            trackViewUrl: nil
        )
    }
}
