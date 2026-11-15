import Foundation
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningDiscArtistLinksTests: XCTestCase {
    func testAlbumCreditsUseAlignedArtistIDs() {
        let disc = makeDisc(artistNames: ["Aimer", "Vaundy"], artistIDs: ["1", "2"])

        let links = ListeningDiscArtistLinks.links(for: disc, lineup: [])

        XCTAssertEqual(links, [
            ListeningDiscArtistLink(name: "Aimer", artistID: "1"),
            ListeningDiscArtistLink(name: "Vaundy", artistID: "2")
        ])
    }

    func testMisalignedIDsFallBackToLineupByName() {
        let disc = makeDisc(artistNames: ["Aimer", "Vaundy"], artistIDs: ["1"])
        let lineup = [ArtistSlot(name: "vaundy", avatarURL: nil, appleMusicArtistID: "42")]

        let links = ListeningDiscArtistLinks.links(for: disc, lineup: lineup)

        XCTAssertEqual(links.map(\.artistID), [nil, "42"])
    }

    func testFeaturedPlaylistUsesItsArtistForASingleCredit() {
        let disc = makeDisc(artistNames: [], trackArtists: ["Aimer"], origin: .featuredPlaylist(artistID: "77"))

        let links = ListeningDiscArtistLinks.links(for: disc, lineup: [])

        XCTAssertEqual(links, [ListeningDiscArtistLink(name: "Aimer", artistID: "77")])
    }

    func testArtistURLUsesStorefrontWhenKnown() {
        let link = ListeningDiscArtistLink(name: "Aimer", artistID: "123")

        XCTAssertEqual(link.appleMusicURL(storefront: "CN")?.absoluteString, "https://music.apple.com/cn/artist/123")
        XCTAssertEqual(link.appleMusicURL(storefront: nil)?.absoluteString, "https://music.apple.com/artist/123")
    }

    func testUnlinkedArtistSearchesAppleMusicByName() {
        let link = ListeningDiscArtistLink(name: "宇多田ヒカル", artistID: nil)

        let url = link.appleMusicURL(storefront: "JP")
        let term = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "term" }?.value

        XCTAssertEqual(url?.path, "/search")
        XCTAssertEqual(term, "宇多田ヒカル")
    }

    func testDiscEncodedBeforeArtistIDsStillDecodes() throws {
        let disc = makeDisc(artistNames: ["Aimer"], artistIDs: ["1"])
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(disc)) as? [String: Any])
        payload.removeValue(forKey: "artistIDs")

        let decoded = try JSONDecoder().decode(ListeningDisc.self, from: JSONSerialization.data(withJSONObject: payload))

        XCTAssertNil(decoded.artistIDs)
        XCTAssertEqual(decoded.artistNames, ["Aimer"])
    }

    func testLineupArtistOpensInAppProfileByAppleMusicID() {
        let lineup = [browseArtist("Vaundy", id: "42", slot: 0), browseArtist("Aimer", id: "7", slot: 1)]

        let match = ListeningDiscArtistLinks.lineupArtist(for: ListeningDiscArtistLink(name: "AIMER", artistID: "7"), in: lineup)

        XCTAssertEqual(match?.slotIndex, 1)
    }

    func testUnlinkedCreditMatchesConnectedLineupArtistByName() {
        let lineup = [browseArtist("Aimer", id: "7", slot: 0)]

        XCTAssertEqual(ListeningDiscArtistLinks.lineupArtist(for: ListeningDiscArtistLink(name: "aimer", artistID: nil), in: lineup)?.id, "7")
    }

    func testOtherArtistsStayOnAppleMusic() {
        let lineup = [browseArtist("Aimer", id: "7", slot: 0), browseArtist("Vaundy", id: nil, slot: 1)]

        // Same name, different Apple Music artist.
        XCTAssertNil(ListeningDiscArtistLinks.lineupArtist(for: ListeningDiscArtistLink(name: "Aimer", artistID: "999"), in: lineup))
        // Lineup artist not yet connected has no in-app page.
        XCTAssertNil(ListeningDiscArtistLinks.lineupArtist(for: ListeningDiscArtistLink(name: "Vaundy", artistID: nil), in: lineup))
        XCTAssertNil(ListeningDiscArtistLinks.lineupArtist(for: ListeningDiscArtistLink(name: "milet", artistID: "3"), in: lineup))
    }

    private func browseArtist(_ name: String, id: String?, slot: Int) -> ListeningBrowseArtist {
        ListeningBrowseArtist(slotIndex: slot, id: id ?? "slot-\(slot)", name: name, artworkURL: nil, appleMusicArtistID: id, albums: [])
    }

    private func makeDisc(
        artistNames: [String],
        artistIDs: [String]? = nil,
        trackArtists: [String] = ["Aimer"],
        origin: ListeningDisc.Origin = .album
    ) -> ListeningDisc {
        let tracks = trackArtists.enumerated().map { index, artist in
            ListeningDiscTrack(CatalogSong(appleMusicSongID: "song-\(index)", title: "Song \(index)", artistName: artist))
        }
        return ListeningDisc(
            id: "disc",
            title: "Disc",
            artworkURL: nil,
            tracks: tracks,
            artistNames: artistNames,
            artistIDs: artistIDs,
            origin: origin
        )
    }
}
