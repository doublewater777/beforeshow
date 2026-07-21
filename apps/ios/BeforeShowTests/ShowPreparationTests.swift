import SwiftData
import XCTest
@testable import BeforeShow

final class ShowPreparationTests: XCTestCase {
    func testPreparationSuggestionsProvideChecklistItems() throws {
        let show = try Show(name: "准备测试现场", date: Date(), startTime: Date(), type: .concert)
        let sections = ShowPreparationGuide().sections(for: show)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { !$0.suggestions.isEmpty })
        XCTAssertTrue(sections.flatMap(\.suggestions).allSatisfy { !$0.text.isEmpty })
    }
}
