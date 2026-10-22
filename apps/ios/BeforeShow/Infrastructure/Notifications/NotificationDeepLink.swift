import Foundation

// MARK: - Deep Link

enum NotificationUserInfoKey {
    static let showID = "showID"
    static let destination = "destination"
    static let feature = "feature"
    static let discID = "discID"
    static let artistID = "artistID"
    static let artistName = "artistName"
}

/// Payload carried in each notification's `userInfo` (and Live Activity links).
/// Tapping opens that show's feature without changing the user's durable Current Show.
struct NotificationDeepLink: Equatable, Sendable {
    enum Destination: String, Codable, Equatable, CaseIterable, Sendable {
        /// 只把 App 带回「当前」，不额外打开详情页。
        case home
        /// 打开「听」，沿用当前现场。
        case listen
        case memoryFragments
        /// 开场记忆通知点进来直接开统一记忆编辑器。
        case memoryCreate
        case route
        case timetable
        case companion
        case widgetGuide
        /// 散场仪式；还没确认散场时先确认散场时间。
        case dispersal
        case footprint
        case nextShow
        case addShow

        var requiresFeaturePresentation: Bool {
            switch self {
            case .memoryFragments, .memoryCreate:
                return true
            default:
                return false
            }
        }
    }

    let showID: UUID
    let destination: Destination
    var feature: RecommendedFeature?
    var discID: String?
    var artistID: String?
    var artistName: String?
    var requestsPlayback = false

    init(showID: UUID, destination: Destination, feature: RecommendedFeature? = nil,
         discID: String? = nil, artistID: String? = nil, artistName: String? = nil) {
        self.showID = showID
        self.destination = destination
        self.feature = feature
        self.discID = discID
        self.artistID = artistID
        self.artistName = artistName
    }

    init?(userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        guard let parsed = Self.parse(userInfo: userInfo) else { return nil }
        let playsDisc = actionIdentifier == ListeningNotificationCategory.playActionIdentifier
        self.init(showID: parsed.showID, destination: playsDisc ? .listen : parsed.destination,
                  feature: parsed.feature, discID: parsed.discID, artistID: parsed.artistID, artistName: parsed.artistName)
        requestsPlayback = playsDisc
    }

    /// 实时活动按钮打开的地址，格式见 `BeforeShowOpenURL`。
    init?(url: URL) {
        guard let parsed = BeforeShowOpenURL.parse(url),
              let showID = UUID(uuidString: parsed.showID),
              let destination = Destination(rawValue: parsed.destination) else {
            return nil
        }
        self.init(showID: showID, destination: destination)
    }

    static func parse(userInfo: [AnyHashable: Any]) -> NotificationDeepLink? {
        guard let rawDestination = userInfo[NotificationUserInfoKey.destination] as? String,
              let destination = Destination(rawValue: rawDestination),
              let rawShowID = userInfo[NotificationUserInfoKey.showID] as? String,
              let showID = UUID(uuidString: rawShowID) else {
            return nil
        }
        let feature = (userInfo[NotificationUserInfoKey.feature] as? String).flatMap(RecommendedFeature.init(rawValue:))
        return NotificationDeepLink(showID: showID, destination: destination, feature: feature,
                                    discID: userInfo[NotificationUserInfoKey.discID] as? String,
                                    artistID: userInfo[NotificationUserInfoKey.artistID] as? String,
                                    artistName: userInfo[NotificationUserInfoKey.artistName] as? String)
    }

    var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            NotificationUserInfoKey.showID: showID.uuidString,
            NotificationUserInfoKey.destination: destination.rawValue
        ]
        if let feature {
            info[NotificationUserInfoKey.feature] = feature.rawValue
        }
        if let discID { info[NotificationUserInfoKey.discID] = discID }
        if let artistID { info[NotificationUserInfoKey.artistID] = artistID }
        if let artistName { info[NotificationUserInfoKey.artistName] = artistName }
        return info
    }
}

extension RecommendedFeature {
    var notificationDestination: NotificationDeepLink.Destination {
        switch self {
        case .widget: return .widgetGuide
        case .companion: return .companion
        case .listen: return .listen
        case .timetable: return .timetable
        case .dispersal: return .dispersal
        case .memoryFragments: return .memoryFragments
        case .footprint: return .footprint
        case .nextShow: return .nextShow
        case .addShow: return .addShow
        }
    }
}
