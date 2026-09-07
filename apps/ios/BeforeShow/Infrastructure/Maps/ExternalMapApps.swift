import CoreLocation
import Foundation
import MapKit
import UIKit

struct MapDestinationCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var latitudeText: String { String(latitude) }
    var longitudeText: String { String(longitude) }
    var commaSeparated: String { "\(latitudeText),\(longitudeText)" }
}

struct ExternalMapDestination: Equatable, Sendable {
    let name: String
    let query: String
    let coordinate: MapDestinationCoordinate?

    init(name: String, query: String, coordinate: MapDestinationCoordinate? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? trimmedQuery : trimmedName
        self.query = trimmedQuery
        self.coordinate = coordinate
    }
}

enum MapDestinationCoordinateResolver {
    /// MapKit/Core Location coordinates use WGS-84. Third-party URL builders must declare
    /// that coordinate system explicitly instead of assuming GCJ-02 / BD-09.
    @MainActor
    static func resolve(query: String) async -> MapDestinationCoordinate? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                return nil
            }
            return MapDestinationCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            // Route opening must still work offline / when local search fails. Callers fall
            // back to the previous text-query deep link in that case.
            return nil
        }
    }
}

/// 外部地图 App：把场馆位置交给系统地图 / 高德 / 百度 / Google 打开。
/// App 内不做路线规划，只负责解析目的地并拼原生深链。
enum ExternalMapApp: String, CaseIterable, Identifiable, Hashable {
    case apple
    case amap
    case baidu
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return BSLocalization.text("Apple 地图")
        case .amap: return BSLocalization.text("高德地图")
        case .baidu: return BSLocalization.text("百度地图")
        case .google: return BSLocalization.text("Google 地图")
        }
    }

    var iconName: String {
        switch self {
        case .apple: return "map"
        case .amap: return "location.north.line"
        case .baidu: return "mappin.and.ellipse"
        case .google: return "globe.americas"
        }
    }

    /// URL scheme 查询白名单（写入 Info.plist `LSApplicationQueriesSchemes`）。
    static let querySchemes = ["iosamap", "baidumap", "comgooglemaps"]

    /// 用于 `canOpenURL` 的 scheme 探针（不带业务参数）。
    var installProbeURL: URL? {
        switch self {
        case .apple: return URL(string: "maps://")
        case .amap: return URL(string: "iosamap://")
        case .baidu: return URL(string: "baidumap://")
        case .google: return URL(string: "comgooglemaps://")
        }
    }

    /// Apple 地图视为始终可用；第三方依赖 `LSApplicationQueriesSchemes` + 是否安装。
    func isInstalled(canOpen: (URL) -> Bool) -> Bool {
        switch self {
        case .apple:
            return true
        case .amap, .baidu, .google:
            guard let probe = installProbeURL else { return false }
            return canOpen(probe)
        }
    }

    static func installed(canOpen: (URL) -> Bool) -> [ExternalMapApp] {
        allCases.filter { $0.isInstalled(canOpen: canOpen) }
    }

    @MainActor
    static var installed: [ExternalMapApp] {
        installed { UIApplication.shared.canOpenURL($0) }
    }

    /// 兼容纯文本目的地。坐标解析失败时仍使用这条路径兜底。
    func openURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nativeURL(for: ExternalMapDestination(name: trimmed, query: trimmed))
    }

    func openURL(for destination: ExternalMapDestination) -> URL? {
        guard !destination.query.isEmpty else { return nil }
        return nativeURL(for: destination)
    }

    func nativeURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nativeURL(for: ExternalMapDestination(name: trimmed, query: trimmed))
    }

    func nativeURL(for destination: ExternalMapDestination) -> URL? {
        switch self {
        case .apple:
            var components = URLComponents(string: "maps://")
            components?.queryItems = [
                URLQueryItem(
                    name: "daddr",
                    value: destination.coordinate?.commaSeparated ?? destination.query
                ),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
            return components?.url

        case .amap:
            var components = URLComponents(string: "iosamap://path")
            var items = [
                URLQueryItem(name: "sourceApplication", value: BSLocalization.text("开场前")),
                URLQueryItem(name: "dname", value: destination.name),
                URLQueryItem(name: "t", value: "0"),
            ]
            if let coordinate = destination.coordinate {
                items.append(URLQueryItem(name: "dlat", value: coordinate.latitudeText))
                items.append(URLQueryItem(name: "dlon", value: coordinate.longitudeText))
                // CLLocationCoordinate2D is WGS-84; let AMap apply the GCJ-02 offset.
                items.append(URLQueryItem(name: "dev", value: "1"))
            } else {
                items.append(URLQueryItem(name: "dev", value: "0"))
            }
            components?.queryItems = items
            return components?.url

        case .baidu:
            var components = URLComponents(string: "baidumap://map/direction")
            var items = [
                URLQueryItem(name: "origin", value: "我的位置"),
                URLQueryItem(
                    name: "destination",
                    value: destination.coordinate.map {
                        "name:\(destination.name)|latlng:\($0.latitudeText),\($0.longitudeText)"
                    } ?? destination.query
                ),
                URLQueryItem(name: "mode", value: "driving"),
                URLQueryItem(name: "src", value: "ios.com.doublewaterapps.beforeshow"),
            ]
            if destination.coordinate != nil {
                items.append(URLQueryItem(name: "coord_type", value: "wgs84"))
            }
            components?.queryItems = items
            return components?.url

        case .google:
            var components = URLComponents(string: "comgooglemaps://")
            components?.queryItems = [
                URLQueryItem(
                    name: "daddr",
                    value: destination.coordinate?.commaSeparated ?? destination.query
                ),
                URLQueryItem(name: "directionsmode", value: "driving"),
            ]
            return components?.url
        }
    }
}

enum MapDestinationQuery {
    /// 用地点信息拼地图目的地；有地址/场馆时不带演出名，避免搜索被节目名带偏。
    static func make(
        venueAddress: String?,
        venueName: String?,
        city: String?,
        showName: String
    ) -> String? {
        let address = trimmed(venueAddress)
        let cityText = trimmed(city)
        // Street-only addresses are ambiguous across cities; append city when absent.
        if let address, let cityText, !address.localizedCaseInsensitiveContains(cityText) {
            return "\(address) \(cityText)"
        }
        if let address { return address }

        let venue = trimmed(venueName)
        if let venue, let cityText, !venue.localizedCaseInsensitiveContains(cityText) {
            return "\(venue) \(cityText)"
        }
        if let venue { return venue }

        let name = showName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cityText, !name.isEmpty {
            return "\(name) \(cityText)"
        }
        if !name.isEmpty { return name }
        return cityText
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
