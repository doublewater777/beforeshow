import SwiftUI
import SwiftData

struct ListeningFeatureRootView: View {
    let isActive: Bool
    @State private var hasPresentedRoom = false
    #if DEBUG
    @State private var fixture: ListeningDebugFixtures? = ListeningFixtureScenario.requested.flatMap { try? ListeningDebugFixtures(scenario: $0) }
    #endif

    var body: some View {
        Group {
            if hasPresentedRoom {
                room
            } else {
                ListeningPreparingView()
            }
        }
        .onAppear { queueRoomPresentationIfNeeded() }
        .onChange(of: isActive) { _, active in
            if active { queueRoomPresentationIfNeeded() }
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
        } else {
            ListenRootView(isActive: isActive)
        }
        #else
        ListenRootView(isActive: isActive)
        #endif
    }

    private func queueRoomPresentationIfNeeded() {
        guard isActive, !hasPresentedRoom else { return }
        Task { @MainActor in
            await Task.yield()
            presentRoomIfNeeded()
        }
    }

    private func presentRoomIfNeeded() {
        guard !hasPresentedRoom else { return }
        hasPresentedRoom = true
        ListeningPlayerWarmup.prepareIfNeeded()
    }
}
