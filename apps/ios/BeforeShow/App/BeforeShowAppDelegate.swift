import Foundation
import UIKit

final class BeforeShowAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = BeforeShowSceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(BeforeShowSceneDelegate.handle(shortcutItem))
    }
}

/// Universal links and URL contexts only feed the retired-invite inbox here; every
/// other URL is routed by SwiftUI `onOpenURL`. iCloud share acceptance from older
/// invites just opens the app.
final class BeforeShowSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        for activity in connectionOptions.userActivities
        where activity.activityType == NSUserActivityTypeBrowsingWeb {
            if let url = activity.webpageURL { deliver(url) }
        }
        for context in connectionOptions.urlContexts { deliver(context.url) }
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = Self.handle(shortcutItem)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        deliver(url)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts { deliver(context.url) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(Self.handle(shortcutItem))
    }

    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" else { return false }
        Task { @MainActor in
            ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
        }
        return true
    }

    private func deliver(_ url: URL) {
        Task { @MainActor in
            if !LegacyCompanionInviteInbox.shared.receive(url) {
                SharedShowInbox.shared.receive(url)
            }
        }
    }
}
