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
            if let room, let show, room.show?.id == show.id {
                ListeningRoomView(room: room, show: show)
            } else if show != nil {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    Text(BSLocalization.text("听"))
                        .font(BSFont.pageTitle)
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    RoundedRectangle(cornerRadius: BSRadius.md).fill(BSColor.Stage.surfaceRaised).frame(height: 200)
                        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSLayout.pageHeaderTopPadding)
            } else {
                ContentUnavailableView {
                    Label(BSLocalization.text("先选择一场现场"), systemImage: "opticaldisc")
                } description: {
                    Text(BSLocalization.text("添加一场演出，开始听歌"))
                }
            }
        }
        .background(BSColor.Stage.background.ignoresSafeArea())
        .task(id: loadKey) {
            guard let show else { room?.stop(); room?.mechanism.motion.stop(); room = nil; return }
            if room == nil { room = ListeningRoomCoordinator(context: context, catalogService: catalogService, artistSearchService: artistSearchService, playbackFactory: playbackFactory) }
            room?.setActive(isActive)
            await room?.load(show: show)
        }
        .onChange(of: isActive) { _, active in
            room?.setActive(active)
            if active, let show { Task { await room?.load(show: show) } }
        }
        .onDisappear { room?.setActive(false) }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: ListeningDisc?
    @State private var showsCabinet = false
    @State private var showsArtists = false
    @State private var stageScale: CGFloat = 1
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                ScrollViewReader { scroll in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: BSSpacing.sm) {
                            catalogStatus
                            ListeningSongCardView(room: room)
                                .padding(.top, BSSpacing.sm)
                            let scale = min((proxy.size.width - BSSpacing.roomy * 2) / room.mechanism.configuration.geometry.canvas.width, ListeningStyle.maximumStageScale)
                            ListeningMachineView(room: room, scale: scale)
                                .coordinateSpace(name: "playerStage")
                                .listeningFrame("stage")
                                .frame(maxWidth: .infinity)
                                .background {
                                    Ellipse().fill(BSColor.Stage.accent.opacity(0.09))
                                        .frame(height: 260).blur(radius: 55).offset(y: 65)
                                }
                                // Reframe the empty upper canvas without changing the model,
                                // hinge, scale, or the coordinate space used for cabinet dragging.
                                .padding(.top, -room.mechanism.configuration.geometry.viewportTop * scale)
                                .zIndex(10)
                            if let notice = room.mechanism.notice {
                                Text(notice)
                                    .font(BSFont.caption)
                                    .foregroundStyle(BSColor.Stage.muted)
                                    .padding(.horizontal, BSSpacing.md)
                                    .padding(.vertical, 5)
                                    .background(BSColor.Stage.surfaceRaised.opacity(0.75), in: Capsule())
                                    .transition(.opacity)
                            }
                            if let error = room.playbackError {
                                Text(error).font(BSFont.caption).foregroundStyle(BSColor.Stage.danger)
                            }
                            if !room.discs.isEmpty {
                                ListeningCabinetView(room: room, scale: stageScale, showAll: { showsCabinet = true }) { detail = $0 }
                            }
                        }
                        .id("listeningTop")
                        .padding(.horizontal, BSSpacing.roomy)
                        .padding(.top, BSSpacing.sm)
                        .padding(.bottom, BSLayout.tabBarContentInset)
                    }
                    .onChange(of: room.mechanism.motion.lid.value > 0.01) { _, opening in
                        if opening { returnToStage(scroll) }
                    }
                    .onChange(of: room.mechanism.isAutomatic) { _, loading in
                        if loading { returnToStage(scroll) }
                    }
                }
            }
        }
        .coordinateSpace(name: "listeningRoom")
        .onPreferenceChange(ListeningFramesKey.self, perform: updateFrames)
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(item: $detail) { disc in
            ListeningDiscDetailView(room: room, disc: disc)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsCabinet) { ListeningCabinetSheet(room: room) }
        .sheet(isPresented: $showsArtists) { ListeningArtistDetailView(room: room, show: show) }
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
    }
    private func returnToStage(_ scroll: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: BSMotion.interface)) {
            scroll.scrollTo("listeningTop", anchor: .top)
        }
    }
    private var topBar: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { showsArtists = true } label: {
                Image(systemName: "person.2")
            }
            .accessibilityLabel(BSLocalization.text("艺人详情"))
            .accessibilityIdentifier("listening.artists")
            if room.mechanism.disc != nil {
                Button { detail = room.mechanism.disc } label: {
                    Image(systemName: "music.note.list")
                }
                .accessibilityLabel(BSLocalization.text("专辑详情"))
                .accessibilityIdentifier("listening.discTracks")
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(BSColor.Stage.foreground)
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
        .padding(.bottom, BSSpacing.sm)
        .background(BSColor.Stage.background)
        .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border.opacity(0.55)).frame(height: 1) }
        .zIndex(1)
    }

    @ViewBuilder private var artistFilter: some View {
        if let onlyID = room.onlyArtistID,
           let artist = show.artists.first(where: { $0.appleMusicArtistID == onlyID }) {
            HStack(spacing: BSSpacing.xs) {
                Circle().fill(BSColor.Stage.accent).frame(width: 6, height: 6)
                Text(BSLocalization.format("正在只听：%@", artist.name))
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                Button(BSLocalization.text("回到整场")) { room.returnToWholeShow() }
                    .font(BSFont.caption.weight(.medium))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 6)
            .background(BSColor.Stage.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: BSRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.sm).stroke(BSColor.Stage.accent.opacity(0.25), lineWidth: 1))
        }
    }
    @ViewBuilder private var catalogStatus: some View {
        artistFilter
        if room.access.authorizationStatus != .authorized {
            HStack {
                Text(BSLocalization.text("连接 Apple Music" )).font(BSFont.caption)
                Spacer()
                if room.access.authorizationStatus == .notDetermined {
                    Button(BSLocalization.text("授权")) { Task { await room.authorize() } }
                } else {
                    Button(BSLocalization.text("打开设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }.font(BSFont.caption).foregroundStyle(BSColor.Stage.accent)
        }
        switch room.presentation {
        case .loading, .loadingCatalog:
            RoundedRectangle(cornerRadius: BSRadius.md).fill(BSColor.Stage.surfaceRaised)
                .frame(height: 52).accessibilityLabel(BSLocalization.text("正在准备唱片"))
        case .noConnectedArtists:
            status("尚未匹配艺人", action: "连接艺人") { showsArtists = true }
        case .cachedWithError:
            status("暂时无法更新", action: "重试") { Task { await room.load(show: show, force: true) } }
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
        stageScale = stage.width / geometry.canvas.width
        let cosine = cos(geometry.tiltDegrees * .pi / 180)
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - stage.minX) / stageScale,
                    y: geometry.hingeY + ((point.y - stage.minY) / stageScale - geometry.hingeY) / cosine)
        }
        for disc in room.discs {
            if let frame = frames["slot:\(disc.id)"] {
                room.mechanism.cabinetSlots[disc.id] = convert(CGPoint(x: frame.midX, y: frame.midY))
                room.mechanism.cabinetScale = frame.width / stageScale / geometry.discDiameter
            }
        }
        if let frame = frames["cabinet"] {
            let origin = convert(frame.origin)
            room.mechanism.cabinetDropZone = CGRect(x: origin.x, y: origin.y, width: frame.width / stageScale, height: frame.height / stageScale / cosine)
        }
    }
}
