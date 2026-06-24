import SwiftUI
import SwiftData

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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Show.self,
            ShowFragment.self,
            ShowFragmentGalleryMediaReference.self,
            ShowFragmentAudioReference.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self,
            ShowNotificationScheduleRecord.self,
            RoundTripPlan.self,
            ShowPreparationPlan.self,
            CandidateSongGroup.self,
            CandidateSong.self,
            ArtistInterestItem.self,
            ShowVideo.self
        ])
    }
}
