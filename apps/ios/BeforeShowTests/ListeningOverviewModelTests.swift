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

    func testReleaseKindReadsCatalogSuffixAndSingleFlag() {
        XCTAssertEqual(ListeningArtistReleases.kind(named("Night - EP")), .ep)
        XCTAssertEqual(ListeningArtistReleases.kind(named("Trippy World - Single")), .single)
        XCTAssertEqual(ListeningArtistReleases.kind(disc("flagged", isSingle: true)), .single)
        XCTAssertEqual(ListeningArtistReleases.kind(named("Epic Tales")), .album)
        XCTAssertEqual(ListeningArtistReleases.displayTitle(named("Trippy World - Single")), "Trippy World")
    }

    func testFeaturedReleasePrefersAlbumThenEPThenSingle() {
        let single = named("New - Single"), ep = named("Mid - EP"), album = named("Old")
        XCTAssertEqual(ListeningArtistReleases.featured([single, ep, album])?.id, album.id)
        XCTAssertEqual(ListeningArtistReleases.featured([single, ep])?.id, ep.id)
        XCTAssertEqual(ListeningArtistReleases.featured([single])?.id, single.id)
    }

    func testPickFeedStartsWithPreviewAndCoversEveryCandidateOnce() {
        let candidates = ["a", "b", "c", "d"].map { disc($0) }
        var offered: [[String]] = []
        let order = ListeningPickOrder.feed(first: candidates[1], candidates: candidates) { remaining in
            offered.append(remaining.map(\.id))
            return remaining.last
        }
        XCTAssertEqual(order.map(\.id), ["b", "d", "c", "a"])
        XCTAssertEqual(offered, [["a", "c", "d"], ["a", "c"], ["a"]])
    }

    func testPickFeedStillCoversEveryCandidateWhenDrawRepeatsOrGivesUp() {
        let candidates = ["a", "b", "c"].map { disc($0) } + [disc("a")]
        let repeating = ListeningPickOrder.feed(first: nil, candidates: candidates) { _ in candidates[0] }
        XCTAssertEqual(Set(repeating.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(repeating.count, 3)
        let empty = ListeningPickOrder.feed(first: nil, candidates: candidates) { _ in nil }
        XCTAssertEqual(empty.map(\.id), ["a", "b", "c"])
    }

    func testLineupSectionsIndexLatinAndPutOthersLast() {
        let sections = ListeningLineupSection.sections([
            artist("Zedd"), artist("aespa"), artist("Björk"), artist("123 Band"), artist("Adele"),
        ])
        XCTAssertEqual(sections.map(\.id), ["A", "B", "Z", "#"])
        XCTAssertEqual(sections[0].artists.map(\.name), ["Adele", "aespa"])
        XCTAssertEqual(ListeningLineupSection.sections([artist("Zedd"), artist("Adele")], query: "ze")
            .flatMap(\.artists).map(\.name), ["Zedd"])
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

    private func artist(_ name: String) -> ListeningBrowseArtist {
        ListeningBrowseArtist(slotIndex: 0, id: name, name: name, artworkURL: nil,
                              appleMusicArtistID: name, albums: [])
    }
}
