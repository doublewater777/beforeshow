@MainActor enum ListeningRoomCache {
    static var shared: ListeningRoomCoordinator?

    static func discardLocalState() {
        shared?.discardLoadedDiscState()
        shared?.mechanism.motion.stop()
        shared = nil
    }
}

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
        _room = State(initialValue: ListeningRoomCache.shared)
    }

    private var show: Show? {
        let id = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
        return shows.first { $0.id == id }
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
                room?.setActive(false)
            }
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
            room?.mechanism.motion.stop()
            room = nil
            ListeningRoomCache.shared = nil
            return
        }
        if room == nil {
            if let cached = ListeningRoomCache.shared, cached.show?.id == show.id {
                room = cached
            } else {
                let next = ListeningRoomCoordinator(
                    context: context,
                    catalogService: catalogService,
                    artistSearchService: artistSearchService,
                    playbackFactory: playbackFactory
                )
                room = next
                ListeningRoomCache.shared = next
            }
        }
        room?.setActive(true)
        if room?.shouldReloadCatalog(for: show) == true {
            await room?.load(show: show)
        }
    }

    private var listeningRootBackground: some View {
        ZStack {
            BSColor.Stage.background
            ListeningStageBackground(
                artworkURL: room?.mechanism.disc?.artworkURL,
                isPlaying: room?.isPlaying == true
            )
        }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ListeningRoomHeader(mode: room.display.roomMode)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSSpacing.sm) {
                        ListeningStageView(room: room, width: proxy.size.width)
                            .frame(maxWidth: .infinity)
                        if room.display.player.recoveryAction != nil {
                            ListeningCurrentSong(room: room)
                        }
                        if let notice = room.mechanism.notice {
                            Text(notice)
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                                .accessibilityIdentifier("listening.mechanismNotice")
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "listeningContent")
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(isPresented: Binding(
            get: { room.cabinet.isPresented },
            set: { if !$0 { room.cabinet.dismiss() } }
        ), onDismiss: room.completeCabinetSelection) {
            ListeningCabinetSheet(room: room)
        }
        .alert(
            BSLocalization.text("暂时未完成"),
            isPresented: Binding(
                get: { room.errorText != nil },
                set: { if !$0 { room.errorText = nil } }
            )
        ) {
            Button(BSLocalization.text("好"), role: .cancel) { room.errorText = nil }
        } message: {
            Text(room.errorText ?? "")
        }
        .onAppear { ListeningPlaybackChromeStore.shared.room = room }
        .onChange(of: room.mechanism.disc?.id) { _, _ in room.manualDiscChanged() }
        .onChange(of: room.mechanism.position) { _, position in
            if position == .seated { room.finalizeManualDiscInsertionIfNeeded() }
        }
        .onChange(of: reduceMotion, initial: true) { _, value in room.mechanism.motion.reducedMotion = value }
        .onChange(of: scenePhase) { _, phase in room.setForeground(phase == .active) }
    }
}
