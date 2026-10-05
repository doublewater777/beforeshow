@MainActor enum ListeningRoomCache {
    static var shared: ListeningRoomCoordinator?

    static func discardLocalState() {
        shared?.discardLoadedDiscState()
        shared?.stopHardwareMotion()
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
                if room == nil, let show {
                    createRoomIfNeeded(for: show)
                    room?.setActive(false)
                    if room?.show?.id != show.id {
                        room?.prepareForDisplay(show: show)
                    }
                }
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
            room?.stopHardwareMotion()
            room = nil
            ListeningRoomCache.shared = nil
            return
        }
        createRoomIfNeeded(for: show)
        room?.setActive(true)
        if catalogService.currentAuthorizationStatus() == .notDetermined {
            await room?.authorize()
            guard isActive, !Task.isCancelled else { return }
        }
        if room?.shouldReloadCatalog(for: show) == true {
            await room?.load(show: show)
        }
    }

    @MainActor
    private func createRoomIfNeeded(for show: Show) {
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
    }

    private var listeningRootBackground: some View {
        ZStack {
            BSColor.Stage.background
            ListeningStageBackground(
                artworkURL: room?.display.hardware.artworkURL,
                phase: room?.atmospherePhase ?? .resting
            )
        }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCabinet = false
    @State private var matchingSlotIndex: Int?
    @State private var matchingArtistName: String = ""

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ListeningRoomHeader(
                    mode: room.display.roomMode,
                    notice: room.display.headerNotice,
                    onRecovery: { room.performListeningRecovery($0) }
                )
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !room.browseArtists.isEmpty {
                            ListeningArtistSelector(
                                artists: room.browseArtists,
                                selection: room.browser.scope,
                                select: room.selectScope,
                                onConnect: { index, name in
                                    matchingSlotIndex = index
                                    matchingArtistName = name
                                }
                            )
                            .padding(.horizontal, -BSSpacing.roomy)
                            .opacity(room.display.player.isPlaybackActive ? BSListeningTokens.selectionRestingOpacity : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: room.display.player.isPlaybackActive)
                        }

                        let geometry = room.hardwareGeometry
                        let scale = (proxy.size.width - BSSpacing.roomy * 2) * BSListeningTokens.playerWidthFraction / geometry.body.width
                        ListeningCabinetView(room: room, scale: scale, showAll: { showsCabinet = true }, showDetails: { room.browser.open($0) }) {
                            catalogStatus
                        }
                        .opacity(room.display.player.isPlaybackActive ? BSListeningTokens.selectionRestingOpacity : 1)
                        .animation(reduceMotion ? nil : BSListeningTokens.selectionAnimation, value: room.display.player.isPlaybackActive)

                        ListeningMachineView(room: room, scale: scale, showDetails: { room.browser.open($0) })
                            .coordinateSpace(name: "playerStage")
                            .listeningFrame("stage")
                            .frame(width: proxy.size.width - BSSpacing.roomy * 2)
                            .padding(.top, -(geometry.viewportTop + BSListeningTokens.stageTopOffset) * scale)

                        ListeningCurrentSong(room: room)
                            .padding(.top, -BSSpacing.lg)

                        if let notice = room.display.hardware.notice {
                            Text(notice)
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("listening.mechanismNotice")
                        }
                    }
                    .coordinateSpace(name: "listeningContent")
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.xs)
                }
            }
        }
        .onPreferenceChange(ListeningFramesKey.self) { room.applyListeningFrames($0) }
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(item: $room.browser.detail) { disc in
            ListeningDiscDetailView(room: room, disc: disc)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsCabinet) { ListeningCabinetSheet(room: room) }
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
        .onChange(of: reduceMotion, initial: true) { _, value in room.setReducedMotion(value) }
        .task {
            while !Task.isCancelled {
                room.tickMechanism()
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        switch room.display.catalogChrome {
        case .preparing:
            ListeningShelfSkeleton()
        case .needsMusicAccess(let prompt):
            ListeningCatalogStatusView(
                title: BSLocalization.text("连接 Apple Music"),
                subtitle: musicAccessSubtitle(prompt),
                icon: "music.note",
                actionTitle: room.display.recoveryAction?.title
            ) {
                if let action = room.display.recoveryAction { room.performListeningRecovery(action) }
            }
        case .connectArtist(let slotIndex, let name, let isBrowsing):
            ListeningCatalogStatusView(
                title: BSLocalization.text("尚未匹配 Apple Music 艺人"),
                subtitle: isBrowsing ? ListeningCopy.text("选择对应的 Apple Music 艺人") : nil,
                icon: isBrowsing ? "link.badge.plus" : "opticaldisc",
                actionTitle: BSLocalization.text("连接艺人")
            ) {
                if let slotIndex {
                    matchingSlotIndex = slotIndex
                    matchingArtistName = name
                }
            }
        case .unavailable(let isStale):
            ListeningCatalogStatusView(
                title: BSLocalization.text(isStale ? "暂时无法更新专场唱片" : "暂时无法载入音乐"),
                icon: "wifi.exclamationmark",
                actionTitle: room.display.recoveryAction?.title
            ) {
                if let action = room.display.recoveryAction { room.performListeningRecovery(action) }
            }
        case .empty:
            ListeningCatalogStatusView(title: BSLocalization.text("暂时没有找到可翻的唱片"))
        }
    }

    private func musicAccessSubtitle(_ prompt: ListeningMusicAccessPrompt) -> String {
        switch prompt {
        case .notDetermined:
            ListeningCopy.text("授权后载入唱片")
        case .denied:
            BSLocalization.text("请在系统设置中允许访问 Apple Music")
        case .restricted:
            ListeningCopy.text("Apple Music 访问受到系统限制，无法在此更改。")
        }
    }
}
