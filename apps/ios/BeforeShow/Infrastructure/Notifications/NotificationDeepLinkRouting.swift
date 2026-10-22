import Foundation
import Observation
import UserNotifications

// MARK: - Deep Link Routing

@MainActor
@Observable
final class NotificationDeepLinkRouter {
    static let shared = NotificationDeepLinkRouter()

    private(set) var featureRootDeepLink: NotificationDeepLink?
    /// The feature root forwards destinations that belong to the visible Current Show
    /// home (companion, timetable, route…) so its owner presents them in place.
    private(set) var currentShowAction: NotificationDeepLink?
    /// A tapped recommendation counts as handled; the feature root records it.
    private(set) var handledRecommendation: NotificationDeepLink?

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
        let deepLink = NotificationDeepLink(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        )
        Task { @MainActor in
            if let deepLink {
                ProductAnalytics.capture(.appOpenedFrom(
                    source: .notification, destination: deepLink.destination.rawValue, feature: deepLink.feature
                ))
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
