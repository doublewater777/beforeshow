import Foundation

enum LiveModeFocusStore {
    static let key = "liveMode.focusedPerformanceID"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
    }

    static func read(defaults: UserDefaults? = LiveModeFocusStore.defaults) -> UUID? {
        defaults?.string(forKey: key).flatMap(UUID.init(uuidString:))
    }
}
