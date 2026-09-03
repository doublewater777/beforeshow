import Foundation

// MARK: - Deep Link

enum NotificationUserInfoKey {
    static let showID = "showID"
    static let destination = "destination"
}

/// Payload carried in each notification's `userInfo`. Tapping opens the target
/// show's destination without changing the user's durable Current Show.
struct NotificationDeepLink: Equatable, Sendable {
    enum Destination: String, Codable, Equatable, CaseIterable, Sendable {
        case home
        /// 散场后那条通知点进来直接开记忆碎片，否则回首页会落空。
        case memoryFragments
        /// 开场记忆通知点进来直接开统一记忆编辑器。
        case memoryCreate
    }

    let showID: UUID
    let destination: Destination

    init(showID: UUID, destination: Destination) {
        self.showID = showID
        self.destination = destination
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let parsed = Self.parse(userInfo: userInfo) else { return nil }
        self = parsed
    }

    static func parse(userInfo: [AnyHashable: Any]) -> NotificationDeepLink? {
        guard let rawDestination = userInfo[NotificationUserInfoKey.destination] as? String,
              let destination = Destination(rawValue: rawDestination),
              let rawShowID = userInfo[NotificationUserInfoKey.showID] as? String,
              let showID = UUID(uuidString: rawShowID) else {
            return nil
        }
        return NotificationDeepLink(showID: showID, destination: destination)
    }

    var userInfo: [AnyHashable: Any] {
        [
            NotificationUserInfoKey.showID: showID.uuidString,
            NotificationUserInfoKey.destination: destination.rawValue
        ]
    }
}

extension ShowNotificationMilestone {
    var deepLinkDestination: NotificationDeepLink.Destination {
        switch self {
        case .afterShow:
            return .memoryFragments
        case .openingMemory:
            return .memoryCreate
        case .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore,
             .oneDayBefore, .showDayMorning, .showDay:
            return .home
        }
    }
}
