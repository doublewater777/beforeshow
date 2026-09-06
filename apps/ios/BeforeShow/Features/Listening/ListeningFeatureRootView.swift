import SwiftUI
import SwiftData

struct ListeningFeatureRootView: View {
    let isActive: Bool
    #if DEBUG
    @State private var fixture: ModelContainer? = ListeningMVPFixture.containerIfRequested()
    #endif
    var body: some View {
        #if DEBUG
        if let fixture {
            ListeningLiveRootView(isActive: isActive).modelContainer(fixture)
        } else {
            ListeningLiveRootView(isActive: isActive)
        }
        #else
        ListeningLiveRootView(isActive: isActive)
        #endif
    }
}
