import Combine
import Foundation
import UserNotifications

// MARK: - Deep Link Routing

@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    static let shared = NotificationDeepLinkRouter()

    @Published private(set) var featureRootDeepLink: NotificationDeepLink?
    /// The feature root forwards destinations that belong to the visible Current Show
    /// home (companion, timetable, route…) so its owner presents them in place.
    @Published private(set) var currentShowAction: NotificationDeepLink?
    /// A tapped recommendation counts as handled; the feature root records it.
    @Published private(set) var handledRecommendation: NotificationDeepLink?

    private init() {}

    func route(to deepLink: NotificationDeepLink) {
        featureRootDeepLink = deepLink
        if deepLink.feature != nil {
            handledRecommendation = deepLink
        }
    }

    @discardableResult
    func consumeFeatureRoot() -> NotificationDeepLink? {
        guard let deepLink = featureRootDeepLink else { return nil }
        featureRootDeepLink = nil
        return deepLink
    }

    func forwardToCurrentShow(_ deepLink: NotificationDeepLink) {
        currentShowAction = deepLink
    }

    @discardableResult
    func consumeCurrentShowAction() -> NotificationDeepLink? {
        guard let deepLink = currentShowAction else { return nil }
        currentShowAction = nil
        return deepLink
    }

    @discardableResult
    func consumeHandledRecommendation() -> NotificationDeepLink? {
        guard let deepLink = handledRecommendation else { return nil }
        handledRecommendation = nil
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
        let featureString = userInfo[NotificationUserInfoKey.feature] as? String
        Task { @MainActor in
            var parsed: [AnyHashable: Any] = [:]
            if let showIDString { parsed[NotificationUserInfoKey.showID] = showIDString }
            if let destinationString { parsed[NotificationUserInfoKey.destination] = destinationString }
            if let featureString { parsed[NotificationUserInfoKey.feature] = featureString }
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
        // Apple recommends handling foreground notifications in-app instead of
        // presenting a duplicate system alert while the user is already here.
        completionHandler([])
    }
}
