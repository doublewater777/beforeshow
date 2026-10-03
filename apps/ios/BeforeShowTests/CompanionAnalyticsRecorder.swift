import Foundation
import PostHog

/// Observe the actual SDK boundary and drop all events before network delivery.
final class CompanionAnalyticsRecorder: @unchecked Sendable {
    struct Event {
        let name: String
        let properties: [String: Any]
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init() {
        let config = PostHogConfig(projectToken: "companion-tests-\(UUID().uuidString)", host: "http://127.0.0.1:1")
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.preloadFeatureFlags = false
        config.setBeforeSend { [weak self] event in
            if event.event.hasPrefix("companion_"), let self {
                lock.lock()
                recorded.append(Event(name: event.event, properties: event.properties))
                lock.unlock()
            }
            return nil
        }
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.optIn()
    }

    func close() {
        PostHogSDK.shared.close()
    }
}
