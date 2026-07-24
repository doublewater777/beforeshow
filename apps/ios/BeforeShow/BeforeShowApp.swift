import SwiftUI
import SwiftData
import UserNotifications

@main
struct BeforeShowApp: App {
    init() {
        #if DEBUG
        UserDefaults.standard.register(defaults: [
            ProEntitlementStorage.appStorageKey: ProEntitlementStorage.encode(
                ProEntitlementStorage.localDebugDefaultEntitlement
            )
        ])
        #endif
        UNUserNotificationCenter.current().delegate = BeforeShowNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Show.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self,
            ShowNotificationScheduleRecord.self
        ])
    }
}
