@MainActor enum ListeningRoomCache {
    static var shared: ListeningRoomCoordinator?
}

import SwiftUI
import SwiftData

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
   private var show: Show? {
       let id = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
       return shows.first { $0.id == id }
   }
   private var loadKey: String {
       guard let show else { return "empty" }
       return show.id.uuidString + show.artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
   }
   var body: some View {
       Group {
           if let room, let show, room.show?.id == show.id, room.initialLoaded {
               ListeningRoomView(room: room, show: show)
           } else if show != nil {
                ListeningPreparingView()
           } else {
                ListeningEmptyView(
                    hasShows: !shows.isEmpty,
                    onAddShow: { isShowingAddShow = true },
                    onOpenShowLibrary: { isShowingShowLibrary = true }
                )
           }
       }
       .animation(.easeInOut(duration: 0.25), value: room?.initialLoaded)
       .background(BSColor.Stage.background.ignoresSafeArea())
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
       .task(id: loadKey) {
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
                    let next = ListeningRoomCoordinator(context: context, catalogService: catalogService, artistSearchService: artistSearchService, playbackFactory: playbackFactory)
                    room = next
                    ListeningRoomCache.shared = next
                }
            }
            room?.setActive(isActive)
            if room?.show?.id != show.id || room?.discs.isEmpty == true {
                await room?.load(show: show)
            }
        }
        .onChange(of: isActive) { _, active in
            room?.setActive(active)
            if active, let show, room?.show?.id != show.id {
                Task { await room?.load(show: show) }
            }
        }
        .onDisappear { room?.setActive(false) }
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
    @State private var toast: BSToastPayload?
   var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSSpacing.sm) {
                        catalogStatus
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
                        }
                        let geometry = room.mechanism.configuration.geometry
                        let scale = (proxy.size.width - BSSpacing.roomy * 2) * BSListeningTokens.playerWidthFraction / geometry.body.width
                        if !room.browseArtists.isEmpty {
                            if !room.shelfDiscs.isEmpty || room.access.authorizationStatus == .authorized {
                                ListeningCabinetView(room: room, scale: scale, showAll: { showsCabinet = true }) {
                                    room.browser.open($0)
                                }
                            }
                        }
                        ListeningMachineView(room: room, scale: scale)
                            .coordinateSpace(name: "playerStage")
                            .listeningFrame("stage")
                            .frame(maxWidth: .infinity)
                            .background {
                                ListeningAtmosphere(
                                    disc: room.mechanism.position == .seated ? room.mechanism.disc : nil,
                                    isPlaying: room.isPlaying
                                )
                            }
                           .padding(.top, -geometry.viewportTop * scale)
                        ListeningCurrentSong(room: room)
                       if let notice = room.mechanism.notice {
                           Text(notice).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                        }
                      if room.track == nil, let error = room.playbackError {
                            Text(error).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.danger)
                        }
                    }
                    .coordinateSpace(name: "listeningContent")
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
                    .padding(.bottom, BSLayout.tabBarContentInset)
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
        .alert(BSLocalization.text("暂时未完成"), isPresented: Binding(get: { room.errorText != nil }, set: { if !$0 { room.errorText = nil } })) {
            Button(BSLocalization.text("好"), role: .cancel) { room.errorText = nil }
        } message: { Text(room.errorText ?? "") }
        .onChange(of: room.mechanism.disc?.id) { _, _ in room.manualDiscChanged() }
        .onChange(of: room.mechanism.isCabinetDragging) { _, dragging in if dragging { room.manualDiscChanged() } }
        .onChange(of: reduceMotion, initial: true) { _, value in room.mechanism.motion.reducedMotion = value }
        .onChange(of: scenePhase) { _, phase in room.setForeground(phase == .active) }
       .task {
           while !Task.isCancelled {
               room.tick()
               try? await Task.sleep(for: .milliseconds(250))
           }
       }
        .bsToastOverlay(toast, bottomPadding: 100)
   }
   private var topBar: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            membershipStatusBadge
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(BSColor.Stage.foreground)
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
        .padding(.bottom, BSSpacing.sm)
        .zIndex(1)
    }

    @ViewBuilder private var membershipStatusBadge: some View {
        if room.isAuthorizing {
            HStack(spacing: 5) {
                ProgressView()
                    .tint(BSColor.Stage.accent)
                    .scaleEffect(0.7)
                Text(BSLocalization.text("连接中…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 0.75))
        } else if room.access.authorizationStatus != .authorized {
            Button {
                if room.access.authorizationStatus == .notDetermined {
                    Task { await room.authorize() }
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                    Text(BSLocalization.text("连接 Music"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.3), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
       } else if room.access.canPlayCatalogContent {
           Button {
                presentToast(.success, message: BSLocalization.text("Apple Music 会员，支持完整播放"))
           } label: {
               HStack(spacing: 5) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 10, weight: .bold))
                    Text(BSLocalization.text("Music 会员"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [BSColor.Stage.accent.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("Apple Music 会员，支持完整播放"))
       } else {
           Button {
                presentToast(.neutral, message: BSLocalization.text("未开通 Apple Music 会员，提供 30 秒官方试听"))
           } label: {
               HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .medium))
                    Text(BSLocalization.text("试听模式"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(BSColor.Stage.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("Apple Music 未订阅，30秒试听模式"))
        }
    }

    @ViewBuilder private var catalogStatus: some View {
        if room.isAuthorizing {
            HStack(spacing: BSSpacing.sm) {
                ProgressView()
                    .tint(BSColor.Stage.accent)
                    .scaleEffect(0.85)
                Text(BSLocalization.text("正在连接 Apple Music…"))
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.accent)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(BSColor.Stage.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.accent.opacity(0.2), lineWidth: 1)
            )
        } else if room.access.authorizationStatus != .authorized {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: room.access.authorizationStatus == .notDetermined ? "music.note" : "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BSLocalization.text("连接 Apple Music"))
                        .font(BSFont.caption.weight(.medium))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(room.access.authorizationStatus == .notDetermined
                         ? BSLocalization.text("授权后可自动检索专场唱片与曲目")
                         : BSLocalization.text("请在系统设置中允许访问 Apple Music"))
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                Spacer()
                if room.access.authorizationStatus == .notDetermined {
                    Button(BSLocalization.text("立即授权")) {
                        Task { await room.authorize() }
                    }
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(BSColor.Stage.accent, in: Capsule())
                } else {
                    Button(BSLocalization.text("打开设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BSColor.Stage.surfaceRaised, in: Capsule())
                    .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(BSColor.Stage.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
        } else if !room.access.canPlayCatalogContent {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
                Text(BSLocalization.text("未开通 Apple Music 会员，提供 30 秒官方试听"))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: 0.75)
            )
        }
        switch room.presentation {
        case .loading, .loadingCatalog:
            HStack(spacing: BSSpacing.sm) {
                ProgressView()
                    .tint(BSColor.Stage.accent)
                    .scaleEffect(0.85)
                Text(BSLocalization.text("正在检索与整理专场唱片…"))
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(BSColor.Stage.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
        case .noConnectedArtists:
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BSColor.Stage.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BSLocalization.text("尚未匹配 Apple Music 艺人"))
                        .font(BSFont.caption.weight(.medium))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(BSLocalization.text("关联演出阵容中的艺人，即可载入专场唱片与曲目"))
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                Spacer()
                Button(BSLocalization.text("连接艺人")) {
                    if let first = room.browseArtists.first(where: { !$0.isConnected }) ?? room.browseArtists.first {
                        matchingSlotIndex = first.slotIndex
                        matchingArtistName = first.name
                    }
                }
                .font(BSFont.caption.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(BSColor.Stage.accent, in: Capsule())
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(BSColor.Stage.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
        case .cachedWithError:
            status("暂时无法更新专场唱片", action: "重试") { Task { await room.load(show: show, force: true) } }
        case .fatalUnavailable:
            status("暂时无法载入音乐", action: "重试") { Task { await room.load(show: show, force: true) } }
        case .needsAuthorization, .noCurrentShow, .ready: EmptyView()
        }
    }

    private func status(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(BSLocalization.text(title)).font(BSFont.caption).foregroundStyle(BSColor.Stage.muted)
            Spacer()
            Button(BSLocalization.text(action), action: perform).font(BSFont.caption)
        }
    }

    private func updateFrames(_ frames: [String: CGRect]) {
        guard let stage = frames["stage"], stage.width > 0 else { return }
        let geometry = room.mechanism.configuration.geometry
        let stageScale = stage.width / geometry.canvas.width
        let cosine = cos(geometry.tiltDegrees * .pi / 180)
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - stage.minX) / stageScale,
                    y: geometry.hingeY + ((point.y - stage.minY) / stageScale - geometry.hingeY) / cosine)
        }
        var newSlots: [String: CGPoint] = [:]
        var newCabinetScale = room.mechanism.cabinetScale
        for disc in room.discs {
            if let frame = frames["slot:\(disc.id)"] {
                newSlots[disc.id] = convert(CGPoint(x: frame.midX, y: frame.midY))
                newCabinetScale = frame.width / stageScale / geometry.discDiameter
            }
        }
        room.mechanism.cabinetSlots = newSlots
        room.mechanism.cabinetScale = newCabinetScale
        if let frame = frames["cabinet"] {
            let origin = convert(frame.origin)
            room.mechanism.cabinetDropZone = CGRect(x: origin.x, y: origin.y, width: frame.width / stageScale, height: frame.height / stageScale / cosine)
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload { toast = nil }
        }
    }
}
