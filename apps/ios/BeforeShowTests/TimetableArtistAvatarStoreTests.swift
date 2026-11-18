import XCTest
@testable import BeforeShow

@MainActor
final class TimetableArtistAvatarStoreTests: XCTestCase {
    private actor StubSearch: ArtistSearchServicing {
        let artists: [String: RecognizedArtist]
        private(set) var queries: [String] = []
        init(artists: [String: RecognizedArtist]) { self.artists = artists }

        func searchArtists(query: String) async throws -> [RecognizedArtist] {
            queries.append(query)
            return artists[query].map { [$0] } ?? []
        }
    }

    private func artist(_ name: String, avatar: String) -> RecognizedArtist {
        RecognizedArtist(id: name, canonicalName: name, avatarURL: URL(string: avatar), appleMusicURL: nil)
    }

    func testLineupAvatarWinsAndRemoteNamesAreSearchedOnlyOnce() async {
        let search = StubSearch(artists: [
            "NewJeans": artist("NewJeans", avatar: "https://a.test/nj.jpg"),
            "落日飞车 Sunset Rollercoaster": artist("Sunset Rollercoaster", avatar: "https://a.test/sr.jpg")
        ])
        let store = TimetableArtistAvatarStore(search: search)
        await store.load(
            artistNames: ["落日飞车 Sunset Rollercoaster", "NewJeans", "万能青年旅店 Omnipotent Youth Society", "无名乐队"],
            lineup: [ArtistSlot(name: "万能青年旅店", avatarURL: "https://a.test/wq.jpg")]
        )

        XCTAssertEqual(store.url(for: "NewJeans")?.absoluteString, "https://a.test/nj.jpg")
        XCTAssertEqual(store.url(for: "落日飞车 Sunset Rollercoaster")?.absoluteString, "https://a.test/sr.jpg")
        XCTAssertEqual(store.url(for: "万能青年旅店 Omnipotent Youth Society")?.absoluteString, "https://a.test/wq.jpg")
        XCTAssertNil(store.url(for: "无名乐队"))
        let queries = await search.queries
        XCTAssertEqual(Set(queries), Set(["落日飞车 Sunset Rollercoaster", "NewJeans", "无名乐队"]))
        XCTAssertEqual(queries.count, 3)
    }
}
