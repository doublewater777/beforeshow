import Foundation
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistAvatarResolverTests: XCTestCase {
    private var cacheURL: URL!
    private var lookup: StubArtworkLookup!
    private var clock: Date!

    override func setUp() async throws {
        cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("avatars-\(UUID().uuidString).json")
        lookup = StubArtworkLookup()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func makeResolver() -> ArtistAvatarResolver {
        ArtistAvatarResolver(lookup: lookup, cacheURL: cacheURL, autoRefresh: false, now: { [unowned self] in self.clock })
    }

    private let official = URL(string: "https://is1.mzstatic.com/artist/official.jpg")!

    func testSameArtistIDShowsTheSameOfficialPhotoAcrossShows() async {
        lookup.results["111"] = .found(official)
        let resolver = makeResolver()

        await resolver.refresh(artistID: "111")

        XCTAssertEqual(resolver.displayURL(artistID: "111", stored: "https://old.example/show-a.jpg"), official)
        XCTAssertEqual(resolver.displayURL(artistID: "111", stored: "https://old.example/show-b.jpg"), official)
        XCTAssertEqual(resolver.displayURL(artistID: "111", stored: nil), official)
    }

    func testSameNameDifferentIDsNeverShareAPhoto() async {
        lookup.results["111"] = .found(official)
        lookup.results["222"] = .noArtwork
        let resolver = makeResolver()

        await resolver.refresh(artistID: "111")
        await resolver.refresh(artistID: "222")

        XCTAssertNil(resolver.displayURL(artistID: "222", stored: nil))
        XCTAssertNotEqual(resolver.displayURL(artistID: "222", stored: "https://old.example/b.jpg"), official)
    }

    func testUnresolvedRecordKeepsOnlyItsOwnStoredImage() {
        let resolver = makeResolver()
        XCTAssertEqual(resolver.displayURL(artistID: "333", stored: " https://old.example/a.jpg "),
                       URL(string: "https://old.example/a.jpg"))
        XCTAssertNil(resolver.displayURL(artistID: "333", stored: nil), "Another show's stored image never propagates")
        XCTAssertEqual(resolver.displayURL(artistID: nil, stored: "https://old.example/u.jpg"),
                       URL(string: "https://old.example/u.jpg"), "Unlinked artists use their own record")
    }

    /// Apple Music confirms the artist has no photo: an old unknown-source image (often song art) is not promoted.
    func testConfirmedMissingOfficialPhotoFallsBackToPlaceholder() async {
        lookup.results["444"] = .noArtwork
        let resolver = makeResolver()
        await resolver.refresh(artistID: "444")
        XCTAssertNil(resolver.displayURL(artistID: "444", stored: "https://is1.mzstatic.com/song-art.jpg"))
    }

    func testNetworkFailureKeepsVerifiedPhotoAndBacksOff() async {
        lookup.results["555"] = .found(official)
        let resolver = makeResolver()
        await resolver.refresh(artistID: "555")

        clock = clock.addingTimeInterval(ArtistAvatarResolver.revalidationInterval + 1)
        lookup.results["555"] = .failure
        await resolver.refresh(artistID: "555")
        XCTAssertEqual(resolver.displayURL(artistID: "555", stored: nil), official)
        let attempts = lookup.calls["555"]

        clock = clock.addingTimeInterval(60)
        await resolver.refreshIfDue(artistID: "555")
        XCTAssertEqual(lookup.calls["555"], attempts, "Backs off after a failure")

        clock = clock.addingTimeInterval(ArtistAvatarResolver.backoff(afterFailures: 1) + 1)
        await resolver.refreshIfDue(artistID: "555")
        XCTAssertEqual(lookup.calls["555"], (attempts ?? 0) + 1)
    }

    func testVerifiedPhotoIsNotRefetchedUntilRevalidationIsDue() async {
        lookup.results["666"] = .found(official)
        let resolver = makeResolver()
        await resolver.refreshIfDue(artistID: "666")
        await resolver.refreshIfDue(artistID: "666")
        XCTAssertEqual(lookup.calls["666"], 1)

        clock = clock.addingTimeInterval(ArtistAvatarResolver.revalidationInterval + 1)
        let updated = URL(string: "https://is1.mzstatic.com/artist/updated.jpg")!
        lookup.results["666"] = .found(updated)
        await resolver.refreshIfDue(artistID: "666")
        XCTAssertEqual(resolver.displayURL(artistID: "666", stored: nil), updated)
    }

    func testOutOfOrderResponseDoesNotOverwriteNewerResult() async {
        let resolver = makeResolver()
        lookup.results["777"] = .found(URL(string: "https://is1.mzstatic.com/artist/slow-old.jpg")!)
        lookup.delays["777"] = .milliseconds(200)
        let slow = Task { await resolver.refresh(artistID: "777") }
        try? await Task.sleep(for: .milliseconds(20))

        lookup.delays["777"] = nil
        lookup.results["777"] = .found(official)
        await resolver.refresh(artistID: "777")
        await slow.value

        XCTAssertEqual(resolver.displayURL(artistID: "777", stored: nil), official)
    }

    func testAccessUnavailableIsNotCachedAsMissingPhoto() async {
        lookup.results["888"] = .accessUnavailable
        let resolver = makeResolver()
        await resolver.refresh(artistID: "888")
        XCTAssertEqual(resolver.displayURL(artistID: "888", stored: "https://old.example/a.jpg"),
                       URL(string: "https://old.example/a.jpg"))
    }

    func testSearchResultWithOfficialPhotoSeedsTheResolverButUnknownSourcesDoNot() {
        let resolver = makeResolver()
        resolver.record(RecognizedArtist(id: "901", canonicalName: "A", avatarURL: official, appleMusicURL: nil,
                                         isOfficialArtistPhoto: true))
        resolver.record(RecognizedArtist(id: "902", canonicalName: "B",
                                         avatarURL: URL(string: "https://is1.mzstatic.com/song.jpg"), appleMusicURL: nil))
        XCTAssertEqual(resolver.displayURL(artistID: "901", stored: nil), official)
        XCTAssertNil(resolver.displayURL(artistID: "902", stored: nil))
    }

    func testVerifiedPhotosSurviveRelaunch() async {
        lookup.results["999"] = .found(official)
        await makeResolver().refresh(artistID: "999")
        XCTAssertEqual(makeResolver().displayURL(artistID: "999", stored: nil), official)
    }
}

@MainActor
private final class StubArtworkLookup: ArtistOfficialArtworkLookup {
    enum Result { case found(URL), noArtwork, accessUnavailable, failure }
    var results: [String: Result] = [:]
    var delays: [String: Duration] = [:]
    var calls: [String: Int] = [:]

    func officialArtwork(artistID: String) async throws -> ArtistOfficialArtwork {
        calls[artistID, default: 0] += 1
        let result = results[artistID]
        if let delay = delays[artistID] { try await Task.sleep(for: delay) }
        switch result {
        case .found(let url): return .photo(url)
        case .noArtwork, nil: return .none
        case .accessUnavailable: return .accessUnavailable
        case .failure: throw URLError(.notConnectedToInternet)
        }
    }
}
