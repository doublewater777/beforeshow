import XCTest
@testable import BeforeShow

final class DynamicCoverTests: XCTestCase {
    func testDynamicFaceStorePersistsPerShowAndClears() {
        let defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        let first = UUID()
        let second = UUID()

        DynamicCoverFaceStore.setDynamicFace(true, for: first, defaults: defaults)
        XCTAssertTrue(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: second, defaults: defaults))

        DynamicCoverFaceStore.clear(showID: first, defaults: defaults)
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        defaults.removePersistentDomain(forName: #file)
    }

    func testDynamicCoverPathStaysBoundToShowDirectory() {
        let showID = UUID()
        XCTAssertTrue(DynamicCover.isValidRelativePath("\(showID.uuidString)/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("other/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("\(showID.uuidString)/../video.mov", showID: showID))
    }
}
