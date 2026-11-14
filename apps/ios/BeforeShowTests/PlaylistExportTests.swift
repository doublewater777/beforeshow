import XCTest
@testable import BeforeShow

final class PlaylistExportTests: XCTestCase {
    private typealias Song = PlaylistExport.Song

    func testTextIsOneSongPerLineAsTitleDashArtist() {
        let songs = [Song(title: "防火墙杀死了我", artistName: "Carsick Cars"), Song(title: "中南海", artistName: "Carsick Cars")]

        XCTAssertEqual(PlaylistExport.text(songs), "防火墙杀死了我 - Carsick Cars\n中南海 - Carsick Cars")
    }

    func testSongWithoutArtistIsJustTheTitle() {
        XCTAssertEqual(PlaylistExport.text([Song(title: "Intro", artistName: "  ")]), "Intro")
    }

    func testRepeatedSongAppearsOnceInFirstPosition() {
        let songs = PlaylistExport.songs([
            Song(title: "中南海", artistName: "Carsick Cars"),
            Song(title: "You Can Listen You Can Talk", artistName: "Carsick Cars"),
            Song(title: " 中南海", artistName: "carsick cars"),
            Song(title: "  ", artistName: "Carsick Cars"),
        ])

        XCTAssertEqual(songs.map(\.title), ["中南海", "You Can Listen You Can Talk"])
    }

    func testImagesHoldAFixedNumberOfSongsEach() {
        let songs = (1...32).map { Song(title: "Song \($0)", artistName: "A") }

        let pages = PlaylistExport.pages(songs)

        XCTAssertEqual(pages.map(\.count), [15, 15, 2])
        XCTAssertEqual(pages.last?.first?.title, "Song 31")
    }

    @MainActor
    func testEachPageRendersToOneImageAtFullWidth() throws {
        let songs = (1...16).map { Song(title: "Song \($0)", artistName: "A") }

        let images = try XCTUnwrap(PlaylistExport.images(songs))

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].size.width * images[0].scale, PlaylistExport.imageWidth * PlaylistExport.imageScale)
        XCTAssertGreaterThan(images[0].size.height, images[1].size.height)
    }
}
