import XCTest
@testable import BeforeShow

final class ArtistAlbumArtworkResolverTests: XCTestCase {

    func testResolvesOwnNewestAlbumArtworkUpgradedTo600() async {
        let session = RoutingMockURLSession { url in
            if url.absoluteString.contains("/search") {
                return Self.searchJSON
            }
            return Self.lookupJSON
        }
        let resolver = ArtistAlbumArtworkResolver(session: session)

        let url = await resolver.artworkURL(forArtistName: "落日飞车")

        // 2026 的 feat. 单曲 artistId 不同被排除,取艺人自己最新的 QUIT QUIETLY。
        XCTAssertEqual(
            url?.absoluteString,
            "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/79/04/79/own-newer.jpg/600x600bb.jpg"
        )
    }

    func testReturnsNilWhenArtistNotFound() async {
        let session = RoutingMockURLSession { _ in #"{"resultCount":0,"results":[]}"# }
        let resolver = ArtistAlbumArtworkResolver(session: session)

        let url = await resolver.artworkURL(forArtistName: "不存在的艺人")

        XCTAssertNil(url)
    }

    func testCachesResultPerArtistName() async {
        let counter = RequestCounter()
        let session = RoutingMockURLSession(counter: counter) { url in
            url.absoluteString.contains("/search") ? Self.searchJSON : Self.lookupJSON
        }
        let resolver = ArtistAlbumArtworkResolver(session: session)

        _ = await resolver.artworkURL(forArtistName: "落日飞车")
        _ = await resolver.artworkURL(forArtistName: "落日飞车")

        XCTAssertEqual(counter.count, 2, "第二次命中缓存,不应再发请求")
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

    func testBestArtworkFallsBackToAnyCollectionWhenNoneAreOwn() {
        let collections = [
            ITunesCollection(wrapperType: "collection", artistId: 999, releaseDate: "2024-01-01T00:00:00Z", artworkUrl100: "https://example.com/b/100x100bb.jpg")
        ]

        let url = ArtistAlbumArtworkResolver.bestArtworkURL(from: collections, artistID: 7)

        XCTAssertEqual(url?.absoluteString, "https://example.com/b/600x600bb.jpg")
    }

    private static let searchJSON = #"{"resultCount":1,"results":[{"wrapperType":"artist","artistName":"落日飞车","artistId":1230293264}]}"#

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
    var handler: @Sendable (URL) -> String

    init(counter: RequestCounter? = nil, handler: @escaping @Sendable (URL) -> String) {
        self.counter = counter
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        counter?.increment()
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(handler(url).utf8), response)
    }
}
