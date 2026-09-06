import SwiftUI
import SwiftData

struct ListeningFeatureRootView: View {
    let isActive: Bool
    #if DEBUG
    @State private var fixture: ListeningDebugFixtures? = ListeningFixtureScenario.requested.flatMap { try? ListeningDebugFixtures(scenario: $0) }
    #endif
    var body: some View {
        #if DEBUG
        if let fixture {
            ListenRootView(isActive: isActive, catalogService: ListeningFixtureCatalog(scenario: fixture.scenario), playbackFactory: { _ in ListeningFixturePlayer() }).modelContainer(fixture.container)
        } else {
            ListenRootView(isActive: isActive)
        }
        #else
        ListenRootView(isActive: isActive)
        #endif
    }
}
