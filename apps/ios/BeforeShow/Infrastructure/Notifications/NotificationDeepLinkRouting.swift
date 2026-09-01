import Combine
import Foundation
import UserNotifications

// MARK: - Deep Link Routing

@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    static let shared = NotificationDeepLinkRouter()

    @Published private(set) var pendingDeepLink: NotificationDeepLink?

    private init() {}

    func route(to deepLink: NotificationDeepLink) {
        pendingDeepLink = deepLink
    }

    @discardableResult
    func consume() -> NotificationDeepLink? {
        // Only clear when non-nil. Assigning `nil` while already `nil` still
        // fires `@Published` and can re-enter `.onReceive` → infinite layout loop
        // (seen as 100% CPU after leaving onboarding into the main TabView).
        guard let deepLink = pendingDeepLink else { return nil }
        pendingDeepLink = nil
        return deepLink
    }
}

/// Reads `userInfo` on notification tap (foreground and cold start) and routes the
/// deep link. Methods are `nonisolated` because the system calls them off the main
/// actor; only Sendable strings are carried into the main-actor task. Stateless, so
/// safe to share as a singleton.
final class BeforeShowNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = BeforeShowNotificationDelegate()

    private override init() {
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let showIDString = userInfo[NotificationUserInfoKey.showID] as? String
        let destinationString = userInfo[NotificationUserInfoKey.destination] as? String
        Task { @MainActor in
            var parsed: [AnyHashable: Any] = [:]
            if let showIDString { parsed[NotificationUserInfoKey.showID] = showIDString }
            if let destinationString { parsed[NotificationUserInfoKey.destination] = destinationString }
            if let deepLink = NotificationDeepLink(userInfo: parsed) {
                NotificationDeepLinkRouter.shared.route(to: deepLink)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 非「快开场了」的节点不带声音，前台只给横幅（见 makeNotificationRequest）。
        if notification.request.content.sound == nil {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
