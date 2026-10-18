import Foundation
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningSearchTests: XCTestCase {
    private func track(_ id: String, _ title: String, _ artist: String) -> ListeningDiscTrack {
        ListeningDiscTrack(CatalogSong(appleMusicSongID: id, title: title, artistName: artist))
    }

    private lazy var compilation = ListeningDisc(
        id: "c1", title: "热门合辑 01", artworkURL: nil,
        tracks: [track("s1", "夜晚的风", "落日飞车"), track("s2", "My Jinji", "落日飞车")],
        artistNames: ["落日飞车"], origin: .compilation(showID: UUID(), number: 1)
    )
    private lazy var album = ListeningDisc(
        id: "a1", title: "Jinji Kikko", artworkURL: nil,
        tracks: [track("s2", "My Jinji", "落日飞车"), track("s3", "Vanilla Villa", "落日飞车")],
        artistNames: ["落日飞车"]
    )
    private lazy var other = ListeningDisc(
        id: "a2", title: "大梦", artworkURL: nil,
        tracks: [track("s4", "如常", "草东没有派对")], artistNames: ["草东没有派对"]
    )

    private var discs: [ListeningDisc] { [compilation, album, other] }

    func testEmptyQueryShowsNothing() {
        let results = ListeningSearch.results(for: "  ", in: discs)
        XCTAssertTrue(results.discs.isEmpty)
        XCTAssertTrue(results.tracks.isEmpty)
    }

    func testMatchesDiscTitleAndArtistAcrossScripts() {
        XCTAssertEqual(ListeningSearch.results(for: "jinji kikko", in: discs).discs.map(\.disc.id), ["a1"])
        XCTAssertEqual(ListeningSearch.results(for: "落日飛車", in: discs).discs.map(\.disc.id), ["c1", "a1"])
    }

    func testTrackMatchOpensItsDiscFocusedOnThatTrackAndIsListedOnce() {
        let results = ListeningSearch.results(for: "my jinji", in: discs)
        XCTAssertTrue(results.discs.isEmpty)
        XCTAssertEqual(results.tracks.count, 1, "The same song on two discs is listed once")
        XCTAssertEqual(results.tracks.first?.disc.id, "c1", "Rack order decides which disc opens")
        XCTAssertEqual(results.tracks.first?.focusTrackID, "s2")
    }

    func testTrackArtistMatches() {
        let results = ListeningSearch.results(for: "草东", in: discs)
        XCTAssertEqual(results.discs.map(\.disc.id), ["a2"])
        XCTAssertEqual(results.tracks.map(\.focusTrackID), ["s4"])
    }
}
