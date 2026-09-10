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
        let query = "梅赛德斯-奔驰文化中心"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.apple.nativeURL(for: query))
        XCTAssertEqual(url.scheme, "maps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, query)
    }

    func testAppleUsesResolvedCoordinateWhenAvailable() throws {
        let query = "梅赛德斯-奔驰文化中心 上海"
        MapNavigationCoordinateCache.shared.store(.init(latitude: 31.2304, longitude: 121.4737), for: query)
        defer { MapNavigationCoordinateCache.shared.removeCoordinate(for: query) }

        let url = try XCTUnwrap(ExternalMapApp.apple.nativeURL(for: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "31.23040000,121.47370000")
    }

    func testAmapNativeUsesPathWithDestinationName() throws {
        let query = "工人体育场"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: query))
        XCTAssertEqual(url.scheme, "iosamap")
        XCTAssertEqual(url.host, "path")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, query)
        XCTAssertEqual(items.first(where: { $0.name == "sourceApplication" })?.value, "开场前")
        XCTAssertNil(items.first(where: { $0.name == "dlat" }))
        XCTAssertNil(items.first(where: { $0.name == "dlon" }))
    }

    func testAmapUsesResolvedDestinationCoordinatesAndWGS84OffsetFlag() throws {
        let query = "工人体育场 北京"
        MapNavigationCoordinateCache.shared.store(.init(latitude: 39.9309, longitude: 116.4465), for: query)
        defer { MapNavigationCoordinateCache.shared.removeCoordinate(for: query) }

        let url = try XCTUnwrap(ExternalMapApp.amap.nativeURL(for: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "dname" })?.value, query)
        XCTAssertEqual(items.first(where: { $0.name == "dlat" })?.value, "39.93090000")
        XCTAssertEqual(items.first(where: { $0.name == "dlon" })?.value, "116.44650000")
        XCTAssertEqual(items.first(where: { $0.name == "dev" })?.value, "1")
        XCTAssertEqual(items.first(where: { $0.name == "t" })?.value, "0")
    }

    func testBaiduNativeUsesDirectionDestinationName() throws {
        let query = "鸟巢"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: query))
        XCTAssertEqual(url.scheme, "baidumap")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, query)
        XCTAssertEqual(items.first(where: { $0.name == "mode" })?.value, "driving")
    }

    func testBaiduUsesResolvedCoordinateAndDeclaresCoordinateType() throws {
        let query = "鸟巢 北京"
        MapNavigationCoordinateCache.shared.store(.init(latitude: 39.9913, longitude: 116.3908), for: query)
        defer { MapNavigationCoordinateCache.shared.removeCoordinate(for: query) }

        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            items.first(where: { $0.name == "destination" })?.value,
            "name:鸟巢 北京|latlng:39.99130000,116.39080000"
        )
        XCTAssertEqual(items.first(where: { $0.name == "coord_type" })?.value, "wgs84")
    }

    func testBaiduNativePreservesSpacesAndNonASCII() throws {
        let query = "梅赛德斯-奔驰文化中心"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.baidu.nativeURL(for: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, query)
    }

    func testGoogleNativeUsesDrivingDirections() throws {
        let query = "Tokyo Dome"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.google.nativeURL(for: query))
        XCTAssertEqual(url.scheme, "comgooglemaps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, query)
        XCTAssertEqual(items.first(where: { $0.name == "directionsmode" })?.value, "driving")
    }

    func testGoogleUsesResolvedCoordinateWhenAvailable() throws {
        let query = "Tokyo Dome Tokyo"
        MapNavigationCoordinateCache.shared.store(.init(latitude: 35.7056, longitude: 139.7519), for: query)
        defer { MapNavigationCoordinateCache.shared.removeCoordinate(for: query) }

        let url = try XCTUnwrap(ExternalMapApp.google.nativeURL(for: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "daddr" })?.value, "35.70560000,139.75190000")
        XCTAssertEqual(items.first(where: { $0.name == "directionsmode" })?.value, "driving")
    }

    func testOpenURLUsesNativeDeepLink() throws {
        let query = "梅奔"
        MapNavigationCoordinateCache.shared.removeCoordinate(for: query)
        let url = try XCTUnwrap(ExternalMapApp.amap.openURL(for: query))
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
