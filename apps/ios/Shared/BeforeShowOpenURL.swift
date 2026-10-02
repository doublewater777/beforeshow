import Foundation

/// 实时活动按钮与 App 共用的打开地址：`beforeshow://open?show=<id>&destination=<raw>`。
enum BeforeShowOpenURL {
    static let scheme = "beforeshow"
    static let host = "open"
    /// 与 App 内 `NotificationDeepLink.Destination` 的原始值一致。
    static let routeDestination = "route"
    static let memoryCreateDestination = "memoryCreate"

    static func make(showID: String, destination: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "show", value: showID),
            URLQueryItem(name: "destination", value: destination)
        ]
        return components.url
    }

    static func parse(_ url: URL) -> (showID: String, destination: String)? {
        guard url.scheme == scheme, url.host == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let showID = items.first(where: { $0.name == "show" })?.value,
              let destination = items.first(where: { $0.name == "destination" })?.value else {
            return nil
        }
        return (showID, destination)
    }
}
