import XCTest
@testable import BeforeShow

final class ShowCoverReferenceTests: XCTestCase {
    private var folder: URL { ShowCoverReference.directory! }

    func testAnImportedCoverIsStoredInsideTheAppNotAsAnAbsolutePath() {
        XCTAssertEqual(ShowCoverReference.stored(fileName: "abc.jpg"), "ShowCovers/abc.jpg")
        XCTAssertEqual(ShowCoverReference.url("ShowCovers/abc.jpg"), folder.appendingPathComponent("abc.jpg"))
    }

    func testAnOlderAbsolutePathFindsTheCoverInTodaysContainer() {
        let old = "file:///var/mobile/Containers/Data/Application/OLD-UUID/Library/Application%20Support/ShowCovers/abc.jpg"
        XCTAssertEqual(ShowCoverReference.url(old), folder.appendingPathComponent("abc.jpg"))
        XCTAssertEqual(ShowCoverReference.localFileName(old), "abc.jpg")
    }

    func testWebCoversAndOtherFilesPassThrough() {
        XCTAssertEqual(ShowCoverReference.url(" https://example.com/a.jpg "), URL(string: "https://example.com/a.jpg"))
        XCTAssertEqual(ShowCoverReference.url("file:///tmp/ShowCovers/a.jpg"), URL(string: "file:///tmp/ShowCovers/a.jpg"),
                       "only Application Support/ShowCovers is ours")
        XCTAssertNil(ShowCoverReference.localFileName("https://example.com/ShowCovers/a.jpg"))
        XCTAssertNil(ShowCoverReference.url(nil))
        XCTAssertNil(ShowCoverReference.url("  "))
    }

    func testAStoredPathCannotLeaveTheCoversFolder() {
        XCTAssertNil(ShowCoverReference.localFileName("ShowCovers/../default.store"))
        XCTAssertNil(ShowCoverReference.localFileName("ShowCovers/a/b.jpg"))
        XCTAssertNil(ShowCoverReference.url("ShowCovers/"))
    }
}
