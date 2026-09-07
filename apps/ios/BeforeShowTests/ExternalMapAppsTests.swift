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
        // District-level address does not contain city name; append city for disambiguation.
        XCTAssertEqual(query, "建邺区江东中路399号 南京")
    }

    func testDestinationAppendsCityToStreetOnlyAddress() {
        let query = MapDestinationQuery.make(
            venueAddress: "人民路1号",
            venueName: "某场馆",
            city: "南京",
            showName: "某演出"
        )
        XCTAssertEqual(query, "人民路1号 南京")
    }

    func testDestinationDoesNotDuplicateCityInsideAddress() {
        let query = MapDestinationQuery.make(
            venueAddress: "南京市人民路1号",
            venueName: "某场馆",
            city: "南京",
            showName: "某演出"
        )
        XCTAssertEqual(query, "南京市人民路1号")
    }

    func testDestinationKeepsAddressWhenCityBlank() {
        let query = MapDestinationQuery.make(
            venueAddress: "人民路1号",
            venueName: "某场馆",
            city: "  ",
            showName: "某演出"
        )
        XCTAssertEqual(query, "人民路1号")
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

    func testAppleNativeUsesResolvedCoordinateWhenAvailable() throws {
        let destination = ExternalMapDestination(
            name: "梅赛德斯-奔驰文化中心",
            query: "世博大道1200号 上海",
            coordinate: MapDestinationCoordinate(latitude: 31.1907, longitude: 121.4897)
        )
        let url = try XCTUnwrap(ExternalMapApp.apple.nativeURL(for: destination))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "31.1907,121.4897")
    }

    func testAmapNativeUsesPathWithDestinationName() throws {
        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: "工人体育场"))
        XCTAssertEqual(url.scheme, "iosamap")
        XCTAssertEqual(url.host, "path")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, "工人体育场")
        XCTAssertEqual(items.first(where: { $0.name == "sourceApplication" })?.value, "开场前")
    }

    func testAmapNativeUsesWGS84DestinationCoordinate() throws {
        let destination = ExternalMapDestination(
            name: "工人体育场",
            query: "北京工人体育场 北京",
            coordinate: MapDestinationCoordinate(latitude: 39.9306, longitude: 116.4469)
        )
        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: destination))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, "工人体育场")
        XCTAssertEqual(items.first(where: { $0.name == "dlat" })?.value, "39.9306")
        XCTAssertEqual(items.first(where: { $0.name == "dlon" })?.value, "116.4469")
        XCTAssertEqual(items.first(where: { $0.name == "dev" })?.value, "1")
        XCTAssertEqual(items.first(where: { $0.name == "t" })?.value, "0")
    }

    func testBaiduNativeUsesDirectionDestinationName() throws {
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: "鸟巢"))
        XCTAssertEqual(url.scheme, "baidumap")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, "鸟巢")
        XCTAssertEqual(items.first(where: { $0.name == "mode" })?.value, "driving")
    }

    func testBaiduNativeUsesNamedWGS84Coordinate() throws {
        let destination = ExternalMapDestination(
            name: "国家体育场（鸟巢）",
            query: "国家体育场 北京",
            coordinate: MapDestinationCoordinate(latitude: 39.9913, longitude: 116.3908)
        )
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: destination))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            items.first(where: { $0.name == "destination" })?.value,
            "name:国家体育场（鸟巢）|latlng:39.9913,116.3908"
        )
        XCTAssertEqual(items.first(where: { $0.name == "coord_type" })?.value, "wgs84")
        XCTAssertEqual(items.first(where: { $0.name == "mode" })?.value, "driving")
    }

    func testBaiduNativePreservesSpacesAndNonASCII() throws {
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: "梅赛德斯-奔驰文化中心"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, "梅赛德斯-奔驰文化中心")
    }

    func testGoogleNativeUsesDrivingDirections() throws {
        let url = try XCTUnwrap(ExternalMapApp.google.nativeURL(for: "Tokyo Dome"))
        XCTAssertEqual(url.scheme, "comgooglemaps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "Tokyo Dome")
        XCTAssertEqual(items.first(where: { $0.name == "directionsmode" })?.value, "driving")
    }

    func testGoogleNativeUsesResolvedCoordinateWhenAvailable() throws {
        let destination = ExternalMapDestination(
            name: "Tokyo Dome",
            query: "Tokyo Dome Tokyo",
            coordinate: MapDestinationCoordinate(latitude: 35.7056, longitude: 139.7519)
        )
        let url = try XCTUnwrap(ExternalMapApp.google.nativeURL(for: destination))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "35.7056,139.7519")
        XCTAssertEqual(items.first(where: { $0.name == "directionsmode" })?.value, "driving")
    }

    func testCoordinateDestinationFallsBackToQueryWhenCoordinateMissing() throws {
        let destination = ExternalMapDestination(
            name: "工人体育场",
            query: "工人体育场 北京"
        )
        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: destination))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(items.first(where: { $0.name == "dlat" }))
        XCTAssertNil(items.first(where: { $0.name == "dlon" }))
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, "工人体育场")
        XCTAssertEqual(items.first(where: { $0.name == "dev" })?.value, "0")
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
