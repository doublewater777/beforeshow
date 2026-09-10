import Foundation
import UIKit

/// 外部地图 App：把场馆位置交给系统地图 / 高德 / 百度 / Google 打开。
/// App 内不做路线规划，只负责拼目的地查询串与深链。
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

    /// 已安装 App 的原生深链；列表已按安装过滤，不再走网页兜底。
    /// 如果路线 sheet 已经完成地理编码，则优先把坐标交给地图 App，避免名称搜索歧义。
    func openURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nativeURL(for: trimmed)
    }

    func nativeURL(for query: String) -> URL? {
        let coordinate = MapNavigationCoordinateCache.shared.coordinate(for: query)
        let coordinateText = coordinate.map(Self.coordinateText)

        switch self {
        case .apple:
            var components = URLComponents(string: "maps://")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: coordinateText ?? query),
            ]
            return components?.url
        case .amap:
            var components = URLComponents(string: "iosamap://path")
            var items = [
                URLQueryItem(name: "sourceApplication", value: BSLocalization.text("开场前")),
                URLQueryItem(name: "dname", value: query),
                URLQueryItem(name: "t", value: "0"),
            ]
            if let coordinate {
                items.append(URLQueryItem(name: "dlat", value: Self.numberText(coordinate.latitude)))
                items.append(URLQueryItem(name: "dlon", value: Self.numberText(coordinate.longitude)))
                // Core Location / CLGeocoder 返回 CLLocation 坐标；交给高德做国测偏移。
                items.append(URLQueryItem(name: "dev", value: "1"))
            }
            components?.queryItems = items
            return components?.url
        case .baidu:
            var components = URLComponents(string: "baidumap://map/direction")
            var destination = query
            var items: [URLQueryItem] = []
            if let coordinate {
                destination = "name:\(query)|latlng:\(Self.coordinateText(coordinate))"
                items.append(URLQueryItem(name: "coord_type", value: "wgs84"))
            }
            items.append(contentsOf: [
                URLQueryItem(name: "destination", value: destination),
                URLQueryItem(name: "mode", value: "driving"),
                URLQueryItem(name: "src", value: "ios.com.doublewaterapps.beforeshow"),
            ])
            components?.queryItems = items
            return components?.url
        case .google:
            var components = URLComponents(string: "comgooglemaps://")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: coordinateText ?? query),
                URLQueryItem(name: "directionsmode", value: "driving"),
            ]
            return components?.url
        }
    }

    private static func coordinateText(_ coordinate: GeocodedCoordinate) -> String {
        "\(numberText(coordinate.latitude)),\(numberText(coordinate.longitude))"
    }

    private static func numberText(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// 路线选择 sheet 打开期间的短生命周期坐标缓存。
/// 目的地 query 仍由 `MapDestinationQuery` 统一生成；这里只负责在用户选择地图前补齐坐标。
final class MapNavigationCoordinateCache: @unchecked Sendable {
    static let shared = MapNavigationCoordinateCache()

    private let lock = NSLock()
    private var activeQuery: String?
    private var coordinates: [String: GeocodedCoordinate] = [:]

    private init() {}

    func rememberActiveQuery(_ query: String?) {
        lock.lock()
        activeQuery = query
        lock.unlock()
    }

    func coordinate(for query: String) -> GeocodedCoordinate? {
        lock.lock()
        defer { lock.unlock() }
        return coordinates[query]
    }

    func prepareActiveQuery() async {
        let snapshot = activeQuerySnapshot()
        guard let query = snapshot.query, !snapshot.alreadyResolved else { return }
        guard let coordinate = try? await CoreLocationGeocoding().resolve(city: nil, address: query) else {
            return
        }
        store(coordinate, for: query)
    }

    /// 仅供确定性单元测试注入坐标，不触发真实地理编码。
    func store(_ coordinate: GeocodedCoordinate, for query: String) {
        lock.lock()
        coordinates[query] = coordinate
        lock.unlock()
    }

    func removeCoordinate(for query: String) {
        lock.lock()
        coordinates.removeValue(forKey: query)
        lock.unlock()
    }

    private func activeQuerySnapshot() -> (query: String?, alreadyResolved: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let query = activeQuery
        return (query, query.flatMap { coordinates[$0] } != nil)
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
        let result: String?

        // Street-only addresses are ambiguous across cities; append city when absent.
        if let address, let cityText, !address.localizedCaseInsensitiveContains(cityText) {
            result = "\(address) \(cityText)"
        } else if let address {
            result = address
        } else {
            let venue = trimmed(venueName)
            if let venue, let cityText, !venue.localizedCaseInsensitiveContains(cityText) {
                result = "\(venue) \(cityText)"
            } else if let venue {
                result = venue
            } else {
                let name = showName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let cityText, !name.isEmpty {
                    result = "\(name) \(cityText)"
                } else if !name.isEmpty {
                    result = name
                } else {
                    result = cityText
                }
            }
        }

        MapNavigationCoordinateCache.shared.rememberActiveQuery(result)
        return result
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
