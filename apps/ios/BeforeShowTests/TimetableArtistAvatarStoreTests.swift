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

    func testTimetablePickerChecksEnglishAliasForConflictingArtistIDs() async throws {
        let name = "落日飞车 Sunset Rollercoaster"
        let a = artist(name, avatar: "https://a.test/a.jpg")
        let b = artist("Sunset Rollercoaster", avatar: "https://a.test/b.jpg")
        let linker = TimetableArtistLinker(search: VariantArtistSearch(results: [
            name: [a],
            "落日飞车": [a],
            "Sunset Rollercoaster": [b]
        ]))

        let resolution = try await linker.resolveCandidates(for: name)
        XCTAssertNil(resolution.automaticMatch,
                     "The timetable editor must reject the same cross-variant ID conflict as lineup import")
        XCTAssertEqual(Set(resolution.candidates.map(\.id)), Set([a.id, b.id]))
    }

    func testTimetablePickerAllowsOneIDAcrossAllNameVariants() async throws {
        let name = "落日飞车 Sunset Rollercoaster"
        let a = artist("Sunset Rollercoaster", avatar: "https://a.test/a.jpg")
        let linker = TimetableArtistLinker(search: VariantArtistSearch(results: [
            name: [a],
            "落日飞车": [a],
            "Sunset Rollercoaster": [a]
        ]))

        let resolution = try await linker.resolveCandidates(for: name)
        XCTAssertEqual(resolution.automaticMatch?.id, a.id)
        XCTAssertEqual(resolution.candidates.map(\.id), [a.id])
    }

    func testTimetablePickerKeepsManualCandidatesWhenAnAliasSearchFails() async throws {
        let name = "落日飞车 Sunset Rollercoaster"
        let a = artist(name, avatar: "https://a.test/a.jpg")
        let linker = TimetableArtistLinker(search: VariantArtistSearch(
            results: [name: [a]],
            failing: "Sunset Rollercoaster"
        ))
        let resolution = try await linker.resolveCandidates(for: name)
        XCTAssertNil(resolution.automaticMatch)
        XCTAssertEqual(resolution.candidates.map(\.id), [a.id],
                       "Partial results remain selectable by the user")
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

private struct VariantArtistSearch: ArtistSearchServicing {
    let results: [String: [RecognizedArtist]]
    var failing: String? = nil

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        if query == failing { throw ArtistSearchError.network }
        return results[query] ?? []
    }
}
