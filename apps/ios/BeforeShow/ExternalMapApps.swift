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
        case .apple: return "Apple 地图"
        case .amap: return "高德地图"
        case .baidu: return "百度地图"
        case .google: return "Google 地图"
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
    func openURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nativeURL(for: trimmed)
    }

    func nativeURL(for query: String) -> URL? {
        switch self {
        case .apple:
            var components = URLComponents(string: "maps://")
            components?.queryItems = [URLQueryItem(name: "daddr", value: query)]
            return components?.url
        case .amap:
            var components = URLComponents(string: "iosamap://path")
            components?.queryItems = [
                URLQueryItem(name: "sourceApplication", value: "开场前"),
                URLQueryItem(name: "dname", value: query),
                URLQueryItem(name: "dev", value: "0"),
                URLQueryItem(name: "t", value: "0"),
            ]
            return components?.url
        case .baidu:
            var components = URLComponents(string: "baidumap://map/direction")
            components?.queryItems = [
                URLQueryItem(name: "destination", value: query),
                URLQueryItem(name: "mode", value: "driving"),
                URLQueryItem(name: "src", value: "ios.com.doublewaterapps.beforeshow"),
            ]
            return components?.url
        case .google:
            var components = URLComponents(string: "comgooglemaps://")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: query),
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
