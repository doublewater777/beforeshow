import XCTest
@testable import BeforeShow

@MainActor
final class TimetableArtistAvatarStoreTests: XCTestCase {
    private struct StubSearch: ArtistSearchServicing {
        let artists: [String: RecognizedArtist]

        func searchArtists(query: String) async throws -> [RecognizedArtist] {
            artists[query].map { [$0] } ?? []
        }
    }

    private func artist(_ name: String, avatar: String) -> RecognizedArtist {
        RecognizedArtist(id: name, canonicalName: name, avatarURL: URL(string: avatar), appleMusicURL: nil)
    }

    func testBilingualNameSplitsIntoHalves() {
        XCTAssertEqual(
            TimetableArtistAvatarStore.candidateQueries(for: "落日飞车 Sunset Rollercoaster"),
            ["落日飞车 Sunset Rollercoaster", "落日飞车", "Sunset Rollercoaster"]
        )
        XCTAssertEqual(TimetableArtistAvatarStore.candidateQueries(for: "NewJeans"), ["NewJeans"])
    }

    func testLineupAvatarWinsAndBilingualNamesMatchByHalf() async {
        let store = TimetableArtistAvatarStore(search: StubSearch(artists: [
            "NewJeans": artist("NewJeans", avatar: "https://a.test/nj.jpg"),
            "Sunset Rollercoaster": artist("Sunset Rollercoaster", avatar: "https://a.test/sr.jpg")
        ]))
        await store.load(
            artistNames: ["落日飞车 Sunset Rollercoaster", "NewJeans", "万能青年旅店 Omnipotent Youth Society", "无名乐队"],
            lineup: [ArtistSlot(name: "万能青年旅店", avatarURL: "https://a.test/wq.jpg")]
        )

        XCTAssertEqual(store.url(for: "NewJeans")?.absoluteString, "https://a.test/nj.jpg")
        XCTAssertEqual(store.url(for: "落日飞车 Sunset Rollercoaster")?.absoluteString, "https://a.test/sr.jpg")
        XCTAssertEqual(store.url(for: "万能青年旅店 Omnipotent Youth Society")?.absoluteString, "https://a.test/wq.jpg")
        XCTAssertNil(store.url(for: "无名乐队"))
    }
}
