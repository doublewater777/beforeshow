import XCTest
@testable import BeforeShow

final class ShowIdentityCopyTests: XCTestCase {
    func testTitleUsesShowNameWithoutAppendingCityStop() {
        let identity = ShowIdentityCopy(
            name: "Noumena 乐队 2026 “地海边缘” 巡演 北京站",
            venueName: "魅现场",
            city: "北京"
        )

        XCTAssertEqual(identity.title, "Noumena 乐队 2026 “地海边缘” 巡演 北京站")
        XCTAssertEqual(identity.venueSummary, "魅现场 · 北京")
        XCTAssertEqual(
            identity.dateVenueLine(dateLine: "9月11日 20:00"),
            "9月11日 20:00 · 魅现场 · 北京"
        )
    }

    func testVenueSummaryDropsCityWhenVenueAlreadyContainsIt() {
        XCTAssertEqual(
            ShowIdentityCopy.venueSummary(venue: "北京工人体育馆", city: "北京"),
            "北京工人体育馆"
        )
    }

    func testVenueSummaryKeepsCityWhenVenueDoesNotContainIt() {
        XCTAssertEqual(
            ShowIdentityCopy.venueSummary(venue: "梅赛德斯-奔驰文化中心", city: "上海"),
            "梅赛德斯-奔驰文化中心 · 上海"
        )
    }

    func testVenueSummaryFallsBackToCityWhenVenueIsMissing() {
        XCTAssertEqual(ShowIdentityCopy.venueSummary(venue: nil, city: "上海"), "上海")
        XCTAssertNil(ShowIdentityCopy.venueSummary(venue: "  ", city: nil))
    }
}
