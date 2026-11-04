import XCTest
@testable import BeforeShow

final class FootprintNumberSongTests: XCTestCase {
    func testOnlyHandPickedNumbersHaveASong() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 7), FootprintNumberSong(number: 7, title: "Seven Nation Army", artist: "The White Stripes"))
        XCTAssertEqual(FootprintNumberSongs.song(for: 10)?.title, "十年")
        XCTAssertNil(FootprintNumberSongs.song(for: 36), "no forced song for a number without a good one")
        XCTAssertNil(FootprintNumberSongs.song(for: 0))
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
