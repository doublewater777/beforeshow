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

// MARK: - Home Lineup Parser

final class HomeLineupParserTests: XCTestCase {
    func testASCIICommaSeparatesNames() {
        XCTAssertEqual(HomeLineupParser.names(from: "艺人 A, 艺人 B, 艺人 C"), ["艺人 A", "艺人 B", "艺人 C"])
    }

    func testFullwidthCommaSeparatesNames() {
        XCTAssertEqual(HomeLineupParser.names(from: "艺人 A，艺人 B，艺人 C"), ["艺人 A", "艺人 B", "艺人 C"])
    }

    func testIdeographicCommaSeparatesNames() {
        XCTAssertEqual(HomeLineupParser.names(from: "艺人 A、艺人 B、艺人 C"), ["艺人 A", "艺人 B", "艺人 C"])
    }

    func testSlashStaysInsideAnArtistName() {
        XCTAssertEqual(HomeLineupParser.names(from: "AC/DC"), ["AC/DC"])
    }

    func testMixedSeparatorsAndWhitespace() {
        XCTAssertEqual(
            HomeLineupParser.names(from: " 艺人 A，艺人 B 、 艺人 C,艺人 D "),
            ["艺人 A", "艺人 B", "艺人 C", "艺人 D"]
        )
    }

    func testLineupRequiresAtLeastThreeNames() {
        XCTAssertEqual(HomeLineupParser.lineup(from: "艺人 A,艺人 B"), [])
        XCTAssertEqual(HomeLineupParser.lineup(from: "艺人 A,艺人 B,艺人 C"), ["艺人 A", "艺人 B", "艺人 C"])
    }

    func testEmptyAndNilArtistProduceNoNames() {
        XCTAssertEqual(HomeLineupParser.names(from: nil), [])
        XCTAssertEqual(HomeLineupParser.names(from: ""), [])
        XCTAssertEqual(HomeLineupParser.names(from: " ,、 "), [])
    }
}
