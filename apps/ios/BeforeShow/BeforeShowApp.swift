import SwiftUI
import SwiftData
import UserNotifications

@main
struct BeforeShowApp: App {
    @UIApplicationDelegateAdaptor(BeforeShowAppDelegate.self) private var appDelegate
    @State private var companionCoordinator = CompanionSharingCoordinator()

    private let modelContainer: ModelContainer = {
        // Companion sharing uses CloudKit CKRecord/CKShare APIs only.
        // Keep SwiftData local — do not mirror the whole store through CloudKit.
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: Show.self,
                CurrentShowSelection.self,
                NotificationSchedulingState.self,
                ShowNotificationScheduleRecord.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

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
                .environment(companionCoordinator)
                .onAppear {
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                }
                .task {
                    await companionCoordinator.refreshAllLinkedShows(
                        in: modelContainer.mainContext
                    )
                }
        }
        .modelContainer(modelContainer)
    }
}
