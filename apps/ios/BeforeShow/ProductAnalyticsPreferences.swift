import Foundation
import PostHog

/// Local preference for anonymous product analytics and session replay.
///
/// Default is on. Turning it off opts the PostHog SDK out so events and
/// session replay stop being sent from this device.
enum ProductAnalyticsPreferences {
    static let appStorageKey = "productAnalyticsEnabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: appStorageKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: appStorageKey)
    }

    static func apply(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: appStorageKey)
        syncPostHog(enabled: enabled)
    }

    static func syncPostHog(enabled: Bool = isEnabled) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }
}
