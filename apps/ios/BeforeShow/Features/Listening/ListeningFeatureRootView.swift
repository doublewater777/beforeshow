import SwiftUI
import SwiftData

@MainActor
enum ListeningChromeBootstrapper {
    static func prepare(
        show: Show?,
        context: ModelContext,
        catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
        artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
            $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
        }
    ) async -> ListeningRoomCoordinator? {
        guard let show else {
            let cached = ListeningRoomCache.shared
            let published = ListeningPlaybackChromeStore.shared.room
            cached?.stop()
            cached?.mechanism.motion.stop()
            if let published, published !== cached {
                published.stop()
                published.mechanism.motion.stop()
            }
            ListeningRoomCache.shared = nil
            ListeningPlaybackChromeStore.shared.room = nil
            return nil
        }

        // A loaded disc is scoped to the Current Show that hydrated it. If Current
        // changes while another tab is visible, do not let the old compact player or
        // transport leak into the new show. Clearing the persisted loaded-disc state
        // also prevents a newly-created coordinator from restoring that stale disc.
        if let cached = ListeningRoomCache.shared,
           let cachedShowID = cached.show?.id,
           cachedShowID != show.id {
            let published = ListeningPlaybackChromeStore.shared.room
            cached.discardLoadedDiscState()
            cached.mechanism.motion.stop()
            if let published, published !== cached {
                published.stop()
                published.mechanism.motion.stop()
            }
            ListeningRoomCache.shared = nil
            ListeningPlaybackChromeStore.shared.room = nil
        }

        let room: ListeningRoomCoordinator
        let createdCandidate: Bool
        if let cached = ListeningRoomCache.shared {
            room = cached
            createdCandidate = false
        } else {
            room = ListeningRoomCoordinator(
                context: context,
                catalogService: catalogService,
                artistSearchService: artistSearchService,
                playbackFactory: playbackFactory
            )
            createdCandidate = true
        }

        // Root bootstrap exists only to restore chrome for a persisted disc. A fresh
        // coordinator with no restored disc must not trigger artist matching, Music
        // access, or catalog IO before the user actually enters Listen.
        guard room.mechanism.hasDisc, room.track != nil else {
            ListeningPlaybackChromeStore.shared.room = nil
            if createdCandidate {
                room.mechanism.motion.stop()
            }
            return nil
        }

        // Publish a restored-disc candidate to the cache before suspension so Listen
        // can adopt this exact coordinator even if the user enters while hydration is
        // still running. Candidates without a restored disc never enter the cache.
        if createdCandidate {
            ListeningRoomCache.shared = room
        }

        // A restored disc is visible immediately on the coordinator, but chrome is
        // not published until the current show and music access have been hydrated.
        // This keeps compact play/pause on the same transport that Listen later adopts
        // and prevents a cold-start tap from choosing preview/metadata capability from
        // the coordinator's initial `.notDetermined` access state.
        if room.shouldReloadCatalog(for: show) {
            await room.load(show: show)
        }
        guard !Task.isCancelled, room.show?.id == show.id else { return nil }

        ListeningPlaybackChromeStore.shared.room = room
        return room
    }
}

struct ListeningRootChromeModifier: ViewModifier {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    private var currentShow: Show? {
        let id = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
        return shows.first { $0.id == id }
    }

    private var currentShowID: UUID? { currentShow?.id }


    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ListeningPolishedBottomChrome(selectedTab: $selectedTab)
            }
            .task(id: currentShowID) {
                _ = await ListeningChromeBootstrapper.prepare(
                    show: currentShow,
                    context: modelContext
                )
            }
    }
}

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
