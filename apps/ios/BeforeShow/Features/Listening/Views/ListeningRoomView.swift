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
        if catalogService.currentAuthorizationStatus() == .notDetermined {
            await room?.authorize()
            guard isActive, !Task.isCancelled else { return }
        }
        if room?.shouldReloadCatalog(for: show) == true {
            await room?.load(show: show)
        }
    }

    private var listeningRootBackground: some View {
        ZStack {
            BSColor.Stage.background
            ListeningStageBackground(
                artworkURL: room?.mechanism.disc?.artworkURL,
                phase: room.map { ListeningAtmospherePhase(room: $0) } ?? .resting
            )
        }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.scenePhase) private var scenePhase
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
                            .opacity(room.isPlaying ? BSListeningTokens.selectionRestingOpacity : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: room.isPlaying)
                        }

                        let geometry = room.mechanism.configuration.geometry
                        let scale = (proxy.size.width - BSSpacing.roomy * 2) * BSListeningTokens.playerWidthFraction / geometry.body.width
                        ListeningCabinetView(room: room, scale: scale, showAll: { showsCabinet = true }, showDetails: { room.browser.open($0) }) {
                            catalogStatus
                        }
                        .opacity(room.isPlaying ? BSListeningTokens.selectionRestingOpacity : 1)
                        .animation(reduceMotion ? nil : BSListeningTokens.selectionAnimation, value: room.isPlaying)

                        ListeningMachineView(room: room, scale: scale)
                            .coordinateSpace(name: "playerStage")
                            .listeningFrame("stage")
                            .frame(width: proxy.size.width - BSSpacing.roomy * 2)
                            .padding(.top, -(geometry.viewportTop + BSListeningTokens.stageTopOffset) * scale)

                        ListeningCurrentSong(room: room)
                            .padding(.top, -BSSpacing.lg)

                        if let notice = room.mechanism.notice {
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
        .onPreferenceChange(ListeningFramesKey.self, perform: updateFrames)
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
                set: { if !$0 { room.errorText = nil } }
            )
        ) {
            Button(BSLocalization.text("好"), role: .cancel) { room.errorText = nil }
        } message: {
            Text(room.errorText ?? "")
        }
        .onChange(of: room.mechanism.disc?.id) { _, _ in room.manualDiscChanged() }
        .onChange(of: room.mechanism.position) { _, position in
            if position == .seated { room.finalizeManualDiscInsertionIfNeeded() }
        }
        .onChange(of: reduceMotion, initial: true) { _, value in room.mechanism.motion.reducedMotion = value }
        .onChange(of: scenePhase) { _, phase in room.setForeground(phase == .active) }
        .task {
            while !Task.isCancelled {
                room.tickMechanism()
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if room.isAuthorizing {
            if room.access.authorizationStatus == .authorized && room.libraryDiscs.isEmpty {
                ListeningShelfSkeleton()
            } else {
                ListeningCatalogStatusView(title: ListeningCopy.text("连接中…"), isLoading: true)
            }
        } else if !room.accessResolved {
            ListeningShelfSkeleton()
        } else if room.access.authorizationStatus != .authorized {
            ListeningCatalogStatusView(
                title: BSLocalization.text("连接 Apple Music"),
                subtitle: room.access.authorizationStatus == .notDetermined
                    ? ListeningCopy.text("授权后载入唱片")
                    : BSLocalization.text("请在系统设置中允许访问 Apple Music"),
                icon: "music.note",
                actionTitle: room.display.recoveryAction?.title
            ) {
                if let action = room.display.recoveryAction { room.performListeningRecovery(action) }
            }
        } else if room.isCatalogEnriching && room.libraryDiscs.isEmpty {
            // Keep the cabinet geometry stable while the selected artist's full
            // albums are still arriving instead of briefly claiming no records exist.
            ListeningShelfSkeleton()
        } else {
            switch room.presentation {
            case .loading, .loadingCatalog:
                ListeningShelfSkeleton()
            case .noConnectedArtists:
                ListeningCatalogStatusView(
                    title: BSLocalization.text("尚未匹配 Apple Music 艺人"),
                    actionTitle: BSLocalization.text("连接艺人")
                ) {
                    if let first = room.browseArtists.first(where: { !$0.isConnected }) {
                        matchingSlotIndex = first.slotIndex
                        matchingArtistName = first.name
                    }
                }
            case .cachedWithError, .fatalUnavailable:
                ListeningCatalogStatusView(
                    title: BSLocalization.text(room.presentation == .cachedWithError ? "暂时无法更新专场唱片" : "暂时无法载入音乐"),
                    icon: "wifi.exclamationmark",
                    actionTitle: room.display.recoveryAction?.title
                ) {
                    if let action = room.display.recoveryAction { room.performListeningRecovery(action) }
                }
            case .needsAuthorization, .noCurrentShow, .ready:
                ListeningCatalogStatusView(title: BSLocalization.text("暂时没有找到可翻的唱片"))
            }
        }
    }

    private func updateFrames(_ frames: [String: CGRect]) {
        guard let stage = frames["stage"], stage.width > 0 else { return }
        let geometry = room.mechanism.configuration.geometry
        let stageScale = stage.width / geometry.canvas.width
        let cosine = cos(geometry.tiltDegrees * .pi / 180)
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - stage.minX) / stageScale,
                y: geometry.hingeY + ((point.y - stage.minY) / stageScale - geometry.hingeY) / cosine
            )
        }
        var newSlots: [String: CGPoint] = [:]
        var newCabinetScale = room.mechanism.cabinetScale
        for disc in room.discs {
            if let frame = frames["slot:\(disc.id)"] {
                newSlots[disc.id] = convert(CGPoint(x: frame.midX, y: frame.midY))
                newCabinetScale = frame.width / stageScale / geometry.discDiameter
            }
        }
        if room.mechanism.cabinetSlots != newSlots {
            room.mechanism.cabinetSlots = newSlots
        }
        if abs(room.mechanism.cabinetScale - newCabinetScale) > 0.001 {
            room.mechanism.cabinetScale = newCabinetScale
        }
        if let frame = frames["cabinet"] {
            let origin = convert(frame.origin)
            let newDropZone = CGRect(
                x: origin.x,
                y: origin.y,
                width: frame.width / stageScale,
                height: frame.height / stageScale / cosine
            )
            if room.mechanism.cabinetDropZone != newDropZone {
                room.mechanism.cabinetDropZone = newDropZone
            }
        }
    }
}
