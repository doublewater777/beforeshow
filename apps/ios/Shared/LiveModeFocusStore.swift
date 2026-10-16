import Foundation

enum LiveModeFocusStore {
    static let key = "liveMode.focusedPerformanceID"

    /// One shared instance so every @AppStorage observing this key sees writes from the others.
    /// UserDefaults is thread-safe.
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)

    static func read(defaults: UserDefaults? = LiveModeFocusStore.defaults) -> UUID? {
        defaults?.string(forKey: key).flatMap(UUID.init(uuidString:))
    }
}
