import XCTest
@testable import BeforeShow

final class ListeningOverviewModelTests: XCTestCase {
    func testPosterTiersFollowLineupOrderAndFlagOverflow() {
        let small = ListeningPosterTiers(Array(1...7))
        XCTAssertEqual(small.headliners, [1, 2])
        XCTAssertEqual(small.second, [3, 4, 5])
        XCTAssertEqual(small.rest, [6, 7])
        XCTAssertFalse(small.hasMore)

        let large = ListeningPosterTiers(Array(1...40))
        XCTAssertEqual(large.rest, [6, 7, 8, 9, 10, 11])
        XCTAssertTrue(large.hasMore)
        XCTAssertEqual(ListeningPosterTiers(Array(1...40), expanded: true).rest, Array(6...40))
    }

    func testArtistReleasesIncludeSinglesNewestFirst() {
        let releases = ListeningArtistReleases.newestFirst([
            disc("old", year: 2018),
            disc("single", year: 2024, isSingle: true),
            disc("new", year: 2023),
            disc("playlist", year: 2025, origin: .featuredPlaylist(artistID: "x")),
            disc("undated"),
        ])
        XCTAssertEqual(releases.map(\.id), ["single", "new", "old", "undated"])
    }

    func testArtistReleasesKeepTheFullerCopyOfARepeatedRelease() {
        let short = ListeningDisc(id: "short", title: "Baby Gotta Go - Single", artworkURL: nil,
                                  tracks: [track("a")])
        let full = ListeningDisc(id: "full", title: "Baby Gotta Go - Single", artworkURL: nil,
                                 tracks: [track("a"), track("b"), track("c")])
        XCTAssertEqual(ListeningArtistReleases.newestFirst([short, full]).map(\.id), ["full"])
    }

    func testFeaturedReleasePrefersAlbumThenNewestSingleOrEP() {
        let single = disc("new", isSingle: true), ep = named("Mid - EP"), album = named("Old")
        XCTAssertEqual(ListeningArtistReleases.featured([single, ep, album])?.id, album.id)
        XCTAssertEqual(ListeningArtistReleases.featured([single, ep])?.id, single.id)
    }

    func testPickFeedStartsWithPreviewAndKeepsTheDrawnOrder() {
        let drawn = ["a", "b", "c", "d"].map { disc($0) }
        XCTAssertEqual(ListeningPickOrder.feed(first: disc("c"), drawn: drawn).map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(ListeningPickOrder.feed(first: nil, drawn: drawn).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(ListeningPickOrder.feed(first: disc("x"), drawn: drawn).map(\.id), ["a", "b", "c", "d"],
                       "a preview outside the pool is not added")
    }

    func testPickFeedKeepsThePlayingRecordOnePageAboveTheOpeningAlbum() {
        let order = ["b", "c", "a"].map { disc($0) }
        XCTAssertEqual(ListeningPickOrder.keeping(disc("a"), above: order).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ListeningPickOrder.keeping(disc("x"), above: order).map(\.id), ["x", "b", "c", "a"],
                       "a playing playlist outside the pick pool is still kept")
        XCTAssertEqual(ListeningPickOrder.keeping(disc("b"), above: order).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(ListeningPickOrder.keeping(nil, above: order).map(\.id), ["b", "c", "a"])
    }

    func testShelfOrderPutsTheOpeningAlbumsInTheMiddle() {
        let order = ["p", "o", "1", "2", "3", "4"].map { disc($0) }
        XCTAssertEqual(ListeningPickOrder.centred(order, leading: 2).map(\.id), ["1", "2", "p", "o", "3", "4"])
        XCTAssertEqual(ListeningPickOrder.centred(order, leading: 1).map(\.id), ["o", "1", "p", "2", "3", "4"])
        XCTAssertEqual(ListeningPickOrder.centred([disc("o")], leading: 1).map(\.id), ["o"])
    }

    func testPickCardOnlyRedrawsWhenEmptyOrItsAlbumLeftThePool() {
        XCTAssertTrue(ListeningPickCardPolicy.needsNewDraw(current: nil, candidateIDs: ["a"]))
        XCTAssertFalse(ListeningPickCardPolicy.needsNewDraw(current: disc("a"), candidateIDs: ["a", "b"]))
        XCTAssertTrue(ListeningPickCardPolicy.needsNewDraw(current: disc("x"), candidateIDs: ["a", "b"]))
        XCTAssertFalse(ListeningPickCardPolicy.needsNewDraw(
            current: disc("mix", origin: .compilation(showID: UUID(), number: 1)), candidateIDs: ["a"]
        ), "a playlist the user stopped on stays on the card")
    }

    private func disc(_ id: String, year: Int? = nil, isSingle: Bool = false,
                      origin: ListeningDisc.Origin = .album) -> ListeningDisc {
        ListeningDisc(
            id: id, title: id, artworkURL: nil, tracks: [],
            releaseDate: year.flatMap { DateComponents(calendar: .current, year: $0, month: 1, day: 1).date },
            isSingle: isSingle, origin: origin
        )
    }

    private func named(_ title: String) -> ListeningDisc {
        ListeningDisc(id: title, title: title, artworkURL: nil, tracks: [])
    }

    private func track(_ id: String) -> ListeningDiscTrack {
        ListeningDiscTrack(CatalogSong(appleMusicSongID: id, title: id, artistName: "A", duration: 100))
    }
}
