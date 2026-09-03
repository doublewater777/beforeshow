import Combine
import Foundation
import UserNotifications

// MARK: - Deep Link Routing

@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    static let shared = NotificationDeepLinkRouter()

    /// Legacy property intentionally remains nil so the old CurrentShowManagementSection
    /// observer is inert. Phase 1 moves ownership to CurrentShowFeatureRootView without
    /// growing that legacy hotspot just to delete its old observer wiring.
    @Published private(set) var pendingDeepLink: NotificationDeepLink?
    @Published private(set) var featureRootDeepLink: NotificationDeepLink?

    private init() {}

    func route(to deepLink: NotificationDeepLink) {
        featureRootDeepLink = deepLink
    }

    @discardableResult
    func consumeFeatureRoot() -> NotificationDeepLink? {
        guard let deepLink = featureRootDeepLink else { return nil }
        featureRootDeepLink = nil
        return deepLink
    }

    /// Legacy no-op-compatible consumer. New notification delivery never populates
    /// `pendingDeepLink`, so feature-level routing cannot be consumed by the old view.
    @discardableResult
    func consume() -> NotificationDeepLink? {
        guard let deepLink = pendingDeepLink else { return nil }
        pendingDeepLink = nil
        return deepLink
    }
}

/// Reads `userInfo` on notification tap and forwards only a value-type route to the
/// main-actor feature root. Tapping never mutates CurrentShowSelection.
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
        if notification.request.content.sound == nil {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
