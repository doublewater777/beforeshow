import XCTest
@testable import BeforeShow

final class AppleMusicArtistSearchServiceTests: XCTestCase {
    func testStubReturnsCannedResultsForExactQuery() async throws {
        let stub = StubArtistSearchService()
        let expected = RecognizedArtist(
            id: "1",
            canonicalName: "陈绮贞",
            avatarURL: URL(string: "https://example.test/avatar.png")
        )
        stub.canned = ["陈绮贞": [expected]]

        let result = try await stub.searchArtists(query: "陈绮贞")
        XCTAssertEqual(result, [expected])
        XCTAssertEqual(stub.requestCount, 1)
    }

    func testStubFallsBackToWildcardWhenQueryMisses() async throws {
        let stub = StubArtistSearchService()
        let wildcard = RecognizedArtist(id: "x", canonicalName: "Wild", avatarURL: nil)
        stub.canned = ["*": [wildcard]]

        let result = try await stub.searchArtists(query: "anything")
        XCTAssertEqual(result, [wildcard])
    }

    func testStubReturnsEmptyForBlankAndMissingKeys() async throws {
        let stub = StubArtistSearchService()
        let blank1 = try await stub.searchArtists(query: "")
        let blank2 = try await stub.searchArtists(query: "  ")
        let missing = try await stub.searchArtists(query: "absent")
        XCTAssertEqual(blank1, [])
        XCTAssertEqual(blank2, [])
        XCTAssertEqual(missing, [])
        XCTAssertEqual(stub.requestCount, 3)
    }

    func testStubAuthStatusIsConfigurable() async {
        let allowed = StubArtistSearchService()
        allowed.status = .authorized
        let allowedStatus = await allowed.requestAuthorizationIfNeeded()
        XCTAssertEqual(allowedStatus, .authorized)

        let denied = StubArtistSearchService()
        denied.status = .denied
        let deniedStatus = await denied.requestAuthorizationIfNeeded()
        XCTAssertEqual(deniedStatus, .denied)
    }

    func testProductionServiceReturnsEmptyForBlankQuery() async throws {
        // Blank query should not even call the catalog.
        let service = AppleMusicArtistSearchService()
        let blank1 = try await service.searchArtists(query: "")
        let blank2 = try await service.searchArtists(query: "   ")
        XCTAssertEqual(blank1, [])
        XCTAssertEqual(blank2, [])
    }
}

