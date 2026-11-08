import SwiftUI
import XCTest
@testable import BeforeShow

final class BSWideLayoutTests: XCTestCase {
    func testPhoneAndNarrowSplitViewStayCompact() {
        XCTAssertFalse(BSWideLayout.isWide(width: 402, sizeClass: .compact))
        XCTAssertFalse(BSWideLayout.isWide(width: 507, sizeClass: .compact))
        XCTAssertFalse(BSWideLayout.isWide(width: 678, sizeClass: .regular))
    }

    func testFullScreenIPadIsWide() {
        XCTAssertTrue(BSWideLayout.isWide(width: 834, sizeClass: .regular))
        XCTAssertTrue(BSWideLayout.isWide(width: 1194, sizeClass: .regular))
    }

    func testLeadingColumnMatchesPhoneInPortraitAndCapsInLandscape() {
        XCTAssertEqual(BSWideLayout.leadingColumnWidth(for: 834), 390)
        XCTAssertEqual(BSWideLayout.leadingColumnWidth(for: 1376), 520)
    }

    func testGridColumnsGrowWithWidth() {
        XCTAssertEqual(BSWideLayout.gridColumnCount(width: 402, sizeClass: .compact), 2)
        XCTAssertEqual(BSWideLayout.gridColumnCount(width: 834, sizeClass: .regular), 3)
        XCTAssertEqual(BSWideLayout.gridColumnCount(width: 1194, sizeClass: .regular), 4)
    }
}
