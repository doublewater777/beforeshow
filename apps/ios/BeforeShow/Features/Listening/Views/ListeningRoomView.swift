import SwiftUI
import SwiftData
import UIKit

private struct ListeningNotificationTaskKey: Equatable {
    let isActive: Bool
    let showID: UUID?
    let link: NotificationDeepLink?
}

struct ListenRootView: View {
    let isActive: Bool
    var catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService()
    var artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService()
    var playbackFactory: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
        $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
    }
    @Environment(\.modelContext) private var context
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var room: ListeningRoomCoordinator?
    @State private var isShowingAddShow = false
    @State private var isShowingShowLibrary = false
    private let notificationRouter = NotificationDeepLinkRouter.shared

    init(
        isActive: Bool,
        catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
        artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
            $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
        }
    ) {
        self.isActive = isActive
        self.catalogService = catalogService
        self.artistSearchService = artistSearchService
        self.playbackFactory = playbackFactory
        _room = State(initialValue: ListeningRoomSessionStore.shared.room)
    }

    private var show: Show? {
        CurrentShowSession().selectCurrentShow(
            from: shows.filter(\.isAttached),
            manualSelection: CurrentShowSelectionStore.canonical(in: selections)
        )
    }

    /// Only Current Show identity owns the root loading task. Artist identity
    /// enrichment happens inside the bound room and must not cancel/restart that
    /// same load when it writes Apple Music IDs back to the Show.
    private var loadKey: String {
        show?.id.uuidString ?? "empty"
    }

    private var activityKey: String {
        "\(loadKey)|\(isActive)"
    }

    var body: some View {
        ZStack {
            if let room, let show, room.show?.id == show.id {
                ListeningRoomView(room: room, show: show)
                    .id(show.id)
            } else if show == nil {
                ListeningEmptyView(
                    hasShows: !shows.isEmpty,
                    onAddShow: { isShowingAddShow = true },
                    onOpenShowLibrary: { isShowingShowLibrary = true }
                )
            }

            if let show, room?.show?.id != show.id {
                ListeningPreparingView(show: show)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .background(listeningRootBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingAddShow) {
            AddShowCoordinatorSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingShowLibrary) {
            NavigationStack {
                CurrentShowLibraryManagementView()
            }
            .presentationDetents([.large])
            .presentationCornerRadius(26)
            .presentationDragIndicator(.visible)
        }
        .task(id: activityKey) {
            guard !Task.isCancelled else { return }
            if isActive {
                if room != nil {
                    // Let tab selection complete its frame before updating active state
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                }
                await activateRoomIfNeeded()
            } else {
                if let show {
                    createRoomIfNeeded(for: show)
                    room?.setActive(false)
                    if let room { ListeningChromeBootstrapper.prepareRoomForCurrentShow(room, show: show) }
                }
                if show == nil { room?.releaseShow() }
                room?.setActive(false)
            }
        }
        .task(id: ListeningNotificationTaskKey(isActive: isActive, showID: show?.id,
                                               link: notificationRouter.featureRootDeepLink)) {
            await openPendingNotification()
        }
        .onChange(of: show.map(ListeningShowInputs.init)) { _, _ in
            if let show { room?.refreshShowInputs(show) }
        }
        .onDisappear {
            // Normal tab switches are handled by the deferred activity task above.
            // Only tear down synchronously if the active Listen root itself leaves.
            if isActive { room?.setActive(false) }
        }
    }

    @MainActor
    private func activateRoomIfNeeded() async {
        guard isActive else { return }
        guard let show else {
            room?.stop()
            room?.releaseShow()
            room = nil
            ListeningRoomSessionStore.shared.adopt(nil)
            return
        }
        createRoomIfNeeded(for: show)
        if let room { ListeningChromeBootstrapper.prepareRoomForCurrentShow(room, show: show) }
        room?.setActive(true)
        if notificationRouter.featureRootDeepLink?.destination == .listen { return }
        if catalogService.currentAuthorizationStatus() == .notDetermined {
            await room?.authorize()
            guard isActive, !Task.isCancelled else { return }
        }
        if room?.shouldReloadCatalog(for: show) == true {
            await room?.load(show: show)
        }
        if let room, room.hasLoadedDisc {
            ListeningRoomSessionStore.shared.publishChrome(room)
        }
    }

    @MainActor
    private func openPendingNotification() async {
        guard isActive, let show,
              let link = notificationRouter.featureRootDeepLink, link.destination == .listen else { return }
        guard await BSNotificationNavigationGate.waitUntilAvailable(), isActive,
              notificationRouter.featureRootDeepLink == link else { return }
        createRoomIfNeeded(for: show)
        guard let room else { return }
        await ListeningNotificationEntry.open(link, show: show, room: room)
        if !Task.isCancelled, notificationRouter.featureRootDeepLink == link {
            notificationRouter.consumeFeatureRoot()
        }
    }

    @MainActor
    private func createRoomIfNeeded(for show: Show) {
        if room == nil {
            if let cached = ListeningRoomSessionStore.shared.room, cached.show?.id == show.id {
                room = cached
            } else {
                let next = ListeningRoomCoordinator(
                    context: context,
                    catalogService: catalogService,
                    artistSearchService: artistSearchService,
                    playbackFactory: playbackFactory
                )
                room = next
                ListeningRoomSessionStore.shared.adopt(next)
            }
        }
    }

    private var listeningRootBackground: some View {
        ZStack {
            BSColor.Stage.background
            ListeningStageBackground(
                artworkURL: room?.loadedDisc?.artworkURL,
                phase: room?.atmospherePhase ?? .resting
            )
        }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @State private var matchingSlotIndex: Int?
    @State private var matchingArtistName: String = ""
    @State private var isSearching = false
    @State private var overviewSheet: ListeningOverviewSheet?
    @State private var pickFeedStart: ListeningPickFeedStart?
    /// The pick card's album. Owned here so switching to Watch and back keeps it.
    @State private var pickCardDisc: ListeningDisc?
    @Bindable private var session = ListeningRoomSessionStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ListeningRoomHeader(
                mode: room.display.roomMode,
                surface: $session.surface,
                notice: session.surface == .listen ? room.display.headerNotice : nil,
                onRecovery: { room.performListeningRecovery($0) },
                onSearch: room.discs.isEmpty || session.surface == .watch ? nil : { isSearching = true }
            )
            if session.surface == .watch {
                ListeningVideosView(lineup: ListeningVideoLineup(ListeningShowInputs(show)))
            } else {
                ListeningOverviewView(
                    room: room,
                    show: show,
                    onOpenSheet: { overviewSheet = $0 },
                    onMatchArtist: matchArtist,
                    onOpenPick: { pickFeedStart = ListeningPickFeedStart(disc: $0) },
                    pickPreview: $pickCardDisc
                )
                .scrollClipDisabled()
            }
        }
        .bsAdaptiveContentWidth()
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(item: $room.browser.detail) { disc in
            ListeningDiscDetailView(room: room, disc: disc)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isSearching) {
            ListeningSearchSheet(room: room)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $overviewSheet) { sheet in
            Group {
                switch sheet {
                case let .artist(id):
                    NavigationStack {
                        if let artist = room.browseArtists.first(where: { $0.id == id }) {
                            ArtistProfileView(reference: ArtistReference(browseArtist: artist, show: show), show: show)
                                .toolbar { BSChromeToolbarCloseButton { overviewSheet = nil } }
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $session.isNowPlayingPresented) {
            ListeningNowPlayingView(room: room, show: show)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $pickFeedStart) { start in
            ListeningPickFeedView(room: room, show: show, startingDisc: start.disc) { stoppedOn in
                if let stoppedOn { pickCardDisc = stoppedOn }
                pickFeedStart = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { matchingSlotIndex != nil },
            set: { if !$0 { matchingSlotIndex = nil } }
        )) {
            if let slot = matchingSlotIndex {
                ListeningArtistMatchSheet(room: room, slotIndex: slot, query: matchingArtistName)
            }
        }
        .alert(
            BSLocalization.text("暂时未完成"),
            isPresented: Binding(
                get: { room.errorText != nil },
                set: { if !$0 { room.dismissError() } }
            )
        ) {
            Button(BSLocalization.text("好"), role: .cancel) { room.dismissError() }
        } message: {
            Text(room.errorText ?? "")
        }
        .listeningPlaybackFailureAlert(room)
        .onReceive(NotificationCenter.default.publisher(for: .listeningOpenPickDisc)) { _ in
            openPickFeed()
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--listen-open-pick") {
                try? await Task.sleep(for: .milliseconds(500))
                openPickFeed()
            }
        }
    }

    private func matchArtist(_ artist: ListeningBrowseArtist) {
        matchingSlotIndex = artist.slotIndex
        matchingArtistName = artist.name
    }

    /// An outside entry opens the feed only when nothing else is on screen, so it never replaces a sheet.
    private func openPickFeed() {
        let isPresenting = overviewSheet != nil || isSearching || matchingSlotIndex != nil
            || room.browser.detail != nil || session.isNowPlayingPresented
        guard !isPresenting, room.showsRack, !room.pickCandidates(filter: .all).isEmpty else { return }
        pickFeedStart = ListeningPickFeedStart(disc: nil)
    }
}

private struct ListeningPickFeedStart: Identifiable {
    let id = UUID()
    let disc: ListeningDisc?
}

extension Notification.Name {
    static let listeningOpenPickDisc = Notification.Name("listening.openPickDisc")
}

extension View {
    /// Like Apple Music, a song that fails to play is reported once in an alert.
    func listeningPlaybackFailureAlert(_ room: ListeningRoomCoordinator) -> some View {
        alert(
            ListeningCopy.text("无法播放"),
            isPresented: Binding(
                get: { room.showsPlaybackFailureAlert },
                set: { room.showsPlaybackFailureAlert = $0 }
            )
        ) {
            Button(BSLocalization.text("好"), role: .cancel) {}
        } message: {
            Text(ListeningCopy.text("这首歌目前无法播放，请稍后再试。"))
        }
    }
}
