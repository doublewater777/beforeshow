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
            room?.stopHardwareMotion()
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
    @State private var matchingSlotIndex: Int?
    @State private var matchingArtistName: String = ""
    @State private var isSearching = false
    @State private var pickDisc: ListeningDisc?
    @State private var pickExhausted = false
    @State private var pickSessionExcluded: Set<String> = []

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ListeningRoomHeader(
                    mode: room.display.roomMode,
                    notice: room.display.headerNotice,
                    onRecovery: { room.performListeningRecovery($0) },
                    onSearch: room.discs.isEmpty ? nil : { isSearching = true },
                    onPickDisc: canOfferDiscPick ? { beginDiscPick() } : nil
                )
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let geometry = room.hardwareGeometry
                        let availableWidth = min(proxy.size.width - BSSpacing.roomy * 2, BSLayout.maxPlayerWidth)
                        let scale = availableWidth * BSListeningTokens.playerWidthFraction / geometry.body.width
                        let groups = room.rackGroups
                        Group {
                            if room.showsRack {
                                ListeningRackView(room: room, groups: groups, scale: scale) { index, name in
                                    matchingSlotIndex = index
                                    matchingArtistName = name
                                }
                                .padding(.horizontal, -BSSpacing.roomy)
                            } else if room.display.catalogChrome == .preparing {
                                ListeningRackSkeleton()
                                    .padding(.horizontal, -BSSpacing.roomy)
                            } else {
                                catalogStatus
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(.top, BSSpacing.md)
                            }
                        }
                        .frame(height: ListeningRackLayout.slotHeight, alignment: .top)
                        .listeningFrame("cabinet")
                        .padding(.top, BSSpacing.sm)

                        ListeningMachineView(room: room, scale: scale, showDetails: { room.browser.open($0) })
                            .coordinateSpace(name: "playerStage")
                            .listeningFrame("stage")
                            .frame(width: availableWidth)
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
                .scrollClipDisabled()
            }
            .bsAdaptiveContentWidth()
        }
        .onPreferenceChange(ListeningFramesKey.self) { room.applyListeningFrames($0) }
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
        .sheet(isPresented: Binding(
            get: { pickDisc != nil || pickExhausted },
            set: { if !$0 { dismissDiscPick() } }
        )) {
            ListeningDiscPickSheet(
                disc: pickDisc,
                show: show,
                canConfirm: !(room.busy || room.mechanism.isAutomatic),
                canRedraw: canRedrawDiscPick,
                exhausted: pickExhausted,
                onConfirm: confirmDiscPick,
                onRedraw: redrawDiscPick,
                onClose: dismissDiscPick
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        .onChange(of: reduceMotion, initial: true) { _, value in room.setReducedMotion(value) }
        .task {
            while !Task.isCancelled {
                room.tickMechanism()
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listeningOpenPickDisc)) { _ in
            beginDiscPick(allowUnplayable: true)
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--listen-open-pick") {
                try? await Task.sleep(for: .milliseconds(500))
                beginDiscPick(allowUnplayable: true)
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        switch room.display.catalogChrome {
        case .preparing:
            ListeningRackSkeleton()
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

    private var canOfferDiscPick: Bool {
        room.showsRack && !reviewPickCandidates().isEmpty
    }

    private var canRedrawDiscPick: Bool {
        reviewPickCandidates().count > 1
    }

    private func beginDiscPick(allowUnplayable: Bool = false) {
        pickSessionExcluded = seatedPickExclusion()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            revealPickedDisc(allowUnplayable: allowUnplayable)
        }
    }

    private func redrawDiscPick() {
        guard let current = pickDisc else { return }
        pickSessionExcluded.insert(current.id)
        let candidates = reviewPickCandidates()
        let candidateIDs = Set(candidates.map(\.id))
        if candidateIDs.isSubset(of: pickSessionExcluded) {
            pickSessionExcluded = [current.id]
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            revealPickedDisc(allowUnplayable: !room.discPresentation(for: current).canLoad)
        }
    }

    private func confirmDiscPick() {
        guard let pickDisc else { return }
        let disc = pickDisc
        dismissDiscPick()
        room.loadPlayableDisc(disc)
    }

    private func dismissDiscPick() {
        pickDisc = nil
        pickExhausted = false
        pickSessionExcluded = []
    }

    private func revealPickedDisc(allowUnplayable: Bool = false) {
        let candidates = allowUnplayable ? reviewPickCandidates() : loadablePickCandidates()
        guard let picked = ListeningDiscPickPolicy.pick(
            showID: show.id,
            scopeKey: ListeningDiscPickPolicy.scopeKey(for: room.browser.scope),
            candidates: candidates,
            familiarSongIDs: room.familiarSongIDs,
            topSongIDs: topSongIDsForPick(),
            excluding: pickSessionExcluded
        ) else {
            pickDisc = nil
            pickExhausted = true
            return
        }
        ListeningDiscPickPolicy.recordDraw(
            showID: show.id,
            scopeKey: ListeningDiscPickPolicy.scopeKey(for: room.browser.scope),
            discID: picked.id
        )
        pickExhausted = false
        pickDisc = picked
    }

    private func loadablePickCandidates() -> [ListeningDisc] {
        ListeningDiscPickCandidates.discs(in: room.rackGroups, scope: room.browser.scope)
            .filter { room.discPresentation(for: $0).canLoad }
    }

    private func reviewPickCandidates() -> [ListeningDisc] {
        let loadable = loadablePickCandidates()
        if !loadable.isEmpty { return loadable }
        return ListeningDiscPickCandidates.discs(in: room.rackGroups, scope: room.browser.scope)
            .filter { !$0.tracks.isEmpty }
    }

    private func seatedPickExclusion() -> Set<String> {
        guard let id = room.mechanism.disc?.id else { return [] }
        return [id]
    }

    private func topSongIDsForPick() -> [String] {
        switch room.browser.scope {
        case .all:
            room.artistPresentations.values.flatMap { $0.top.prefix(5).map(\.id) }
        case let .artist(id):
            room.artistPresentations[id]?.top.map(\.id) ?? []
        }
    }
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
