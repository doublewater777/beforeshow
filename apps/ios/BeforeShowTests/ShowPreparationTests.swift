import SwiftData
import XCTest
@testable import BeforeShow

final class ShowPreparationTests: XCTestCase {
    func testPreparationSuggestionsProvideChecklistItems() throws {
        let show = try Show(name: "准备测试现场", date: Date(), startTime: Date())
        let sections = ShowPreparationGuide().sections(for: show)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { !$0.suggestions.isEmpty })
        XCTAssertTrue(sections.flatMap(\.suggestions).allSatisfy { !$0.text.isEmpty })
    }

    func testMultiDayShowGetsLongerStayComfortTip() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start)!
        let multiDay = try Show(
            name: "跨天现场",
            date: start,
            startTime: start,
            endDate: end
        )
        let singleDay = try Show(
            name: "单日现场",
            date: start,
            startTime: start
        )

        let multiTips = ShowPreparationGuide().sections(for: multiDay).flatMap(\.suggestions).map(\.text)
        let singleTips = ShowPreparationGuide().sections(for: singleDay).flatMap(\.suggestions).map(\.text)

        XCTAssertTrue(multiTips.contains(where: { $0.contains("跨天停留") }))
        XCTAssertFalse(singleTips.contains(where: { $0.contains("跨天停留") }))
    }
}
