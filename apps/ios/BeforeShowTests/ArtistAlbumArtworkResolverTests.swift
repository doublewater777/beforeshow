import XCTest
@testable import BeforeShow

final class ArtistAlbumArtworkResolverTests: XCTestCase {

    func testResolvesOwnNewestAlbumArtworkUpgradedTo600() async {
        let session = RoutingMockURLSession { _ in Self.lookupJSON }
        let resolver = ArtistAlbumArtworkResolver(session: session, search: ArtworkArtistSearchStub())

        let url = await resolver.artworkURL(forArtistName: "落日飞车")

        // 2026 的 feat. 单曲 artistId 不同被排除,取艺人自己最新的 QUIT QUIETLY。
        XCTAssertEqual(
            url?.absoluteString,
            "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/79/04/79/own-newer.jpg/600x600bb.jpg"
        )
    }

    func testReturnsNilWhenArtistNotFound() async {
        let session = RoutingMockURLSession { _ in #"{"resultCount":0,"results":[]}"# }
        let resolver = ArtistAlbumArtworkResolver(session: session, search: ArtworkArtistSearchStub(candidates: []))

        let url = await resolver.artworkURL(forArtistName: "不存在的艺人")

        XCTAssertNil(url)
    }

    func testUnrelatedOrAmbiguousArtistDoesNotSupplyArtwork() async {
        for candidates in [
            [RecognizedArtist(id: "1230293264", canonicalName: "落日飞车 Live", avatarURL: nil, appleMusicURL: nil)],
            [RecognizedArtist(id: "1230293264", canonicalName: "落日飞车", avatarURL: nil, appleMusicURL: nil),
             RecognizedArtist(id: "999", canonicalName: "落日飞车", avatarURL: nil, appleMusicURL: nil)]
        ] {
            let session = RoutingMockURLSession { _ in Self.lookupJSON }
            let resolver = ArtistAlbumArtworkResolver(session: session, search: ArtworkArtistSearchStub(candidates: candidates))
            let url = await resolver.artworkURL(forArtistName: "落日飞车")
            XCTAssertNil(url, "A partial or ambiguous name must not select the first artist")
        }
    }

    func testCachesResultPerArtistName() async {
        let counter = RequestCounter()
        let session = RoutingMockURLSession(counter: counter) { _ in Self.lookupJSON }
        let search = ArtworkArtistSearchStub()
        let resolver = ArtistAlbumArtworkResolver(session: session, search: search)

        _ = await resolver.artworkURL(forArtistName: "落日飞车")
        _ = await resolver.artworkURL(forArtistName: "落日飞车")

        XCTAssertEqual(counter.count, 1, "第二次命中缓存,不应再发请求")
        let queries = await search.queries
        XCTAssertEqual(queries.count, 1)
    }

    func testCachesConfirmedMissesWithoutRepeatingSearch() async {
        let counter = RequestCounter()
        let session = RoutingMockURLSession(counter: counter) { _ in #"{"resultCount":0,"results":[]}"# }
        let search = ArtworkArtistSearchStub(candidates: [])
        let resolver = ArtistAlbumArtworkResolver(session: session, search: search)

        let first = await resolver.artworkURL(forArtistName: "不存在的艺人")
        let second = await resolver.artworkURL(forArtistName: "不存在的艺人")

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(counter.count, 0)
        let queries = await search.queries
        XCTAssertEqual(queries.count, 1)
    }

    func testConfirmedIDsBypassNameSearchAndDoNotShareCacheForSameName() async {
        let session = RoutingMockURLSession { url in
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "id" }!.value!
            return "{\"results\":[{\"wrapperType\":\"collection\",\"artistId\":\(id),\"artworkUrl100\":\"https://example.com/\(id)/100x100.jpg\"}]}"
        }
        let search = ArtworkArtistSearchStub(candidates: [])
        let resolver = ArtistAlbumArtworkResolver(session: session, search: search)
        let first = await resolver.artworkURL(forArtistName: "Same Name", artistID: "123")
        let second = await resolver.artworkURL(forArtistName: "Same Name", artistID: "456")
        XCTAssertEqual(first?.absoluteString, "https://example.com/123/600x600.jpg")
        XCTAssertEqual(second?.absoluteString, "https://example.com/456/600x600.jpg")
        let queries = await search.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testTransientLookupFailureCanRetryWithinSameLaunch() async {
        let counter = RequestCounter()
        let session = RoutingMockURLSession(counter: counter) { _ in
            if counter.count == 1 { throw URLError(.notConnectedToInternet) }
            return Self.lookupJSON
        }
        let resolver = ArtistAlbumArtworkResolver(session: session, search: ArtworkArtistSearchStub())
        let first = await resolver.artworkURL(forArtistName: "落日飞车")
        let second = await resolver.artworkURL(forArtistName: "落日飞车")
        XCTAssertNil(first)
        XCTAssertEqual(second?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/79/04/79/own-newer.jpg/600x600bb.jpg")
        XCTAssertEqual(counter.count, 2)
    }

    func testBestArtworkSkipsNonCollectionsAndMissingArtwork() {
        let collections = [
            ITunesCollection(wrapperType: "artist", artistId: 7, releaseDate: nil, artworkUrl100: nil),
            ITunesCollection(wrapperType: "collection", artistId: 7, releaseDate: "2026-01-01T00:00:00Z", artworkUrl100: nil),
            ITunesCollection(wrapperType: "collection", artistId: 7, releaseDate: "2025-05-01T00:00:00Z", artworkUrl100: "https://example.com/a/100x100bb.jpg")
        ]

        let url = ArtistAlbumArtworkResolver.bestArtworkURL(from: collections, artistID: 7)

        XCTAssertEqual(url?.absoluteString, "https://example.com/a/600x600bb.jpg")
    }

    func testBestArtworkRejectsOtherArtistsCollections() {
        let collections = [
            ITunesCollection(wrapperType: "collection", artistId: 999, releaseDate: "2024-01-01T00:00:00Z", artworkUrl100: "https://example.com/b/100x100bb.jpg")
        ]

        let url = ArtistAlbumArtworkResolver.bestArtworkURL(from: collections, artistID: 7)

        XCTAssertNil(url)
    }

    private static let lookupJSON = #"{"resultCount":3,"results":[{"wrapperType":"collection","artistId":1230293264,"releaseDate":"2018-03-14T00:00:00Z","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/47/24/0a/own-older.jpg/100x100bb.jpg"},{"wrapperType":"collection","artistId":1230293264,"releaseDate":"2025-08-08T00:00:00Z","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/79/04/79/own-newer.jpg/100x100bb.jpg"},{"wrapperType":"collection","artistId":344112604,"releaseDate":"2026-01-28T00:00:00Z","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/70/a7/bd/featuring.jpg/100x100bb.jpg"}]}"#
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

private struct RoutingMockURLSession: URLSessionProtocol {
    var counter: RequestCounter?
    var handler: @Sendable (URL) throws -> String

    init(counter: RequestCounter? = nil, handler: @escaping @Sendable (URL) throws -> String) {
        self.counter = counter
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        counter?.increment()
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(try handler(url).utf8), response)
    }
}

private actor ArtworkArtistSearchStub: ArtistSearchServicing {
    let candidates: [RecognizedArtist]
    private(set) var queries: [String] = []

    init(candidates: [RecognizedArtist] = [RecognizedArtist(id: "1230293264", canonicalName: "落日飞车", avatarURL: nil, appleMusicURL: nil)]) {
        self.candidates = candidates
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        queries.append(query)
        return candidates
    }
}
