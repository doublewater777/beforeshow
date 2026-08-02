import XCTest
@testable import BeforeShow

final class ExternalMapAppsTests: XCTestCase {
    func testDestinationPrefersAddressOverVenueAndDropsShowName() {
        let query = MapDestinationQuery.make(
            venueAddress: " 建邺区江东中路399号 ",
            venueName: "南京奥体中心体育馆",
            city: "南京",
            showName: "周杰伦嘉年华"
        )
        XCTAssertEqual(query, "建邺区江东中路399号")
    }

    func testDestinationJoinsVenueAndCityWhenNoAddress() {
        let query = MapDestinationQuery.make(
            venueAddress: nil,
            venueName: "梅赛德斯-奔驰文化中心",
            city: "上海",
            showName: "某巡回演唱会"
        )
        XCTAssertEqual(query, "梅赛德斯-奔驰文化中心 上海")
    }

    func testDestinationDoesNotDuplicateCityInsideVenueName() {
        let query = MapDestinationQuery.make(
            venueAddress: nil,
            venueName: "南京奥体中心体育馆",
            city: "南京",
            showName: "测试"
        )
        // city is substring of venue → keep venue only
        XCTAssertEqual(query, "南京奥体中心体育馆")
    }

    func testDestinationFallsBackToShowNameAndCity() {
        let query = MapDestinationQuery.make(
            venueAddress: " ",
            venueName: nil,
            city: "上海",
            showName: "某音乐节"
        )
        XCTAssertEqual(query, "某音乐节 上海")
    }

    func testDestinationReturnsNilWhenEverythingEmpty() {
        XCTAssertNil(
            MapDestinationQuery.make(
                venueAddress: "  ",
                venueName: nil,
                city: "",
                showName: "   "
            )
        )
    }

    func testAppleNativeUsesDirectionsDestination() throws {
        let url = try XCTUnwrap(ExternalMapApp.apple.nativeURL(for: "梅赛德斯-奔驰文化中心"))
        XCTAssertEqual(url.scheme, "maps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "梅赛德斯-奔驰文化中心")
    }

    func testAmapNativeUsesPathWithDestinationName() throws {
        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: "工人体育场"))
        XCTAssertEqual(url.scheme, "iosamap")
        XCTAssertEqual(url.host, "path")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, "工人体育场")
        XCTAssertEqual(items.first(where: { $0.name == "sourceApplication" })?.value, "开场前")
    }

    func testBaiduNativeUsesDirectionDestinationName() throws {
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: "鸟巢"))
        XCTAssertEqual(url.scheme, "baidumap")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, "name:鸟巢")
        XCTAssertEqual(items.first(where: { $0.name == "mode" })?.value, "driving")
    }

    func testGoogleNativeUsesDrivingDirections() throws {
        let url = try XCTUnwrap(ExternalMapApp.google.nativeURL(for: "Tokyo Dome"))
        XCTAssertEqual(url.scheme, "comgooglemaps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "Tokyo Dome")
        XCTAssertEqual(items.first(where: { $0.name == "directionsmode" })?.value, "driving")
    }

    func testOpenURLUsesNativeDeepLink() throws {
        let url = try XCTUnwrap(ExternalMapApp.amap.openURL(for: "梅奔"))
        XCTAssertEqual(url.scheme, "iosamap")
    }

    func testOpenURLReturnsNilForBlankQuery() {
        XCTAssertNil(ExternalMapApp.apple.openURL(for: "   "))
    }

    func testAppleIsAlwaysTreatedAsInstalled() {
        XCTAssertTrue(ExternalMapApp.apple.isInstalled { _ in false })
    }

    func testInstalledFiltersByCanOpenProbe() {
        let installed = ExternalMapApp.installed { url in
            url.scheme == "iosamap" || url.scheme == "baidumap"
        }
        XCTAssertEqual(installed, [.apple, .amap, .baidu])
    }

    func testInstalledOnlyAppleWhenNoThirdPartyMaps() {
        let installed = ExternalMapApp.installed { _ in false }
        XCTAssertEqual(installed, [.apple])
    }

    func testAllAppsExposeTitles() {
        XCTAssertEqual(
            ExternalMapApp.allCases.map(\.title),
            ["Apple 地图", "高德地图", "百度地图", "Google 地图"]
        )
    }
}
