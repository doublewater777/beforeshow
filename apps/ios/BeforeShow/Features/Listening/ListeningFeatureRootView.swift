import SwiftUI
import SwiftData

struct ListeningFeatureRootView: View {
    let isActive: Bool
    #if DEBUG
    @State private var fixture: ListeningDebugFixtures? = ListeningFixtureScenario.requested.flatMap { try? ListeningDebugFixtures(scenario: $0) }
    #endif

    var body: some View {
        room
            .onAppear {
                if isActive { ListeningPlayerWarmup.prepareIfNeeded() }
            }
            .onChange(of: isActive) { _, active in
                if active { ListeningPlayerWarmup.prepareIfNeeded() }
            }
    }

    @ViewBuilder
    private var room: some View {
        #if DEBUG
        if let fixture {
            ListenRootView(
                isActive: isActive,
                catalogService: ListeningFixtureCatalog(scenario: fixture.scenario),
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { _ in ListeningFixturePlayer() }
            )
            .modelContainer(fixture.container)
            .task(id: fixture.seededDisc?.id ?? fixture.mosaicSeededDisc?.id) {
                let disc = fixture.seededDisc ?? fixture.mosaicSeededDisc
                guard let disc else { return }
                while !Task.isCancelled {
                    if let room = ListeningRoomCache.shared, room.show != nil {
                        room.seedDisc(disc)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        } else {
            ListenRootView(isActive: isActive)
        }
        #else
        ListenRootView(isActive: isActive)
        #endif
    }
}
