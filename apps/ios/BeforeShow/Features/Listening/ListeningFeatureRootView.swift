import SwiftUI
import SwiftData

@MainActor
enum ListeningChromeBootstrapper {
    static func prepareRoomForCurrentShow(_ room: ListeningRoomCoordinator, show: Show) {
        guard room.show?.id != show.id else { return }
        if room.show != nil {
            ListeningRoomSessionStore.shared.unpublishChrome()
            room.discardLoadedDiscState()
        }
        room.prepareForDisplay(show: show)
        ListeningRoomSessionStore.shared.adopt(room)
    }

    static func prepare(
        show: Show?,
        context: ModelContext,
        catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
        artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
            $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
        }
    ) async -> ListeningRoomCoordinator? {
        let session = ListeningRoomSessionStore.shared
        guard let show else {
            session.clear(stoppingTransport: true)
            return nil
        }

        // A loaded disc is scoped to the Current Show that hydrated it. If Current
        // changes while another tab is visible, do not let the old compact player or
        // transport leak into the new show. Clearing the persisted loaded-disc state
        // also prevents a newly-created coordinator from restoring that stale disc.
        if let cached = session.room,
           let cachedShowID = cached.show?.id,
           cachedShowID != show.id {
            cached.discardLoadedDiscState()
            session.clear(stoppingTransport: false)
        }

        let room: ListeningRoomCoordinator
        let createdCandidate: Bool
        if let cached = session.room {
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
        guard room.hasLoadedDisc, room.track != nil else {
            session.unpublishChrome()
            if createdCandidate {
                room.stopHardwareMotion()
            }
            return nil
        }

        // Publish a restored-disc candidate before suspension so Listen can adopt this
        // exact coordinator even if the user enters while hydration is still running.
        // Candidates without a restored disc never enter the session.
        if createdCandidate {
            session.adopt(room)
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

        session.publishChrome(room)
        return room
    }
}

extension EnvironmentValues {
    @Entry var rootTabSelection: Binding<BeforeShowTab>?
    @Entry var isRootTabActive = true
}

/// Root pages own the bottom chrome so a push slides it away with the page
/// and an interactive pop brings it back in step with the gesture.
struct RootBottomChromeModifier: ViewModifier {
    @Environment(\.rootTabSelection) private var selection

    func body(content: Content) -> some View {
        if let selection {
            content
                .bsBottomBar {
                    ListeningPolishedBottomChrome(selectedTab: selection)
                        .padding(.bottom, BSSpacing.xs)
                }
        } else {
            content
        }
    }
}

extension View {
    func bsRootBottomChrome() -> some View {
        modifier(RootBottomChromeModifier())
    }
}

struct ListeningRootChromeModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]

    private var currentShow: Show? {
        CurrentShowSession().selectCurrentShow(
            from: shows.filter(\.isAttached),
            manualSelection: CurrentShowSelectionStore.canonical(in: selections)
        )
    }

    private var currentShowID: UUID? { currentShow?.id }

    func body(content: Content) -> some View {
        content
            .task {
                ListeningPlayerWarmup.prepareIfNeeded()
            }
            .task(id: currentShowID) {
                _ = await ListeningChromeBootstrapper.prepare(
                    show: currentShow,
                    context: modelContext
                )
            }
            .onChange(of: scenePhase) { _, phase in
                guard let room = ListeningRoomSessionStore.shared.room else { return }
                let isForeground = phase == .active
                room.setForeground(isForeground)
                if isForeground {
                    Task { await room.refreshMusicAccessAfterForeground() }
                }
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
            .bsRootBottomChrome()
    }

    @ViewBuilder
    private var room: some View {
        #if DEBUG
        if let fixture {
            ListenRootView(
                isActive: isActive,
                catalogService: ListeningFixtureCatalog(scenario: fixture.scenario),
                artistSearchService: ListeningFixtureArtistSearch(fails: fixture.scenario == .artistSearchFailure),
                playbackFactory: { ListeningFixturePlayer(source: $0) }
            )
            .modelContainer(fixture.container)
            .task(id: fixture.seededDisc?.id ?? fixture.mosaicSeededDisc?.id) {
                let disc = fixture.seededDisc ?? fixture.mosaicSeededDisc
                guard let disc else { return }
                while !Task.isCancelled {
                    if let room = ListeningRoomSessionStore.shared.room, room.show != nil {
                        room.seedDisc(disc)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            // `--listen-open-detail` opens a shelf disc (with artwork when there is one) for simulator captures.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--listen-open-detail") else { return }
                while !Task.isCancelled {
                    if let room = ListeningRoomSessionStore.shared.room, let disc = room.discs.first(where: { $0.artworkURL != nil }) ?? room.discs.first {
                        room.browser.detail = disc
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
