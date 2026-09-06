import SwiftUI
import SwiftData

struct ListenRootView: View {
    let isActive: Bool
    var catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService()
    var playbackFactory: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
        $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
    }
    @Environment(\.modelContext) private var context
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var selectedShowID: UUID?
    @State private var room: ListeningRoomCoordinator?
    @State private var addingShow = false
    private var show: Show? {
        let id = selectedShowID ?? CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
        return shows.first { $0.id == id }
    }
    private var loadKey: String {
        guard let show else { return "empty" }
        return show.id.uuidString + show.artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
    }
    var body: some View {
        Group {
            if let room, let show, room.show?.id == show.id {
                ListeningRoomView(room: room, shows: shows, show: show, isActive: isActive, selectedShowID: $selectedShowID)
            } else if let show {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    Text(show.name).font(.title2)
                    RoundedRectangle(cornerRadius: BSRadius.md).fill(BSColor.Stage.surfaceRaised).frame(height: 200)
                        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
                }.padding(BSSpacing.lg)
            } else {
                ContentUnavailableView {
                    Label(BSLocalization.text("先选择一场现场"), systemImage: "opticaldisc")
                } description: {
                    Text(BSLocalization.text("添加一场演出，开始听歌"))
                } actions: {
                    Menu(BSLocalization.text("选择现场")) {
                        ForEach(shows) { item in Button(item.name) { selectedShowID = item.id } }
                        Button(BSLocalization.text("添加演出")) { addingShow = true }
                    }.buttonStyle(BSPrimaryButtonStyle())
                }
            }
        }
        .background(BSColor.Stage.background.ignoresSafeArea())
        .sheet(isPresented: $addingShow) { AddShowCoordinatorSheet { selectedShowID = $0 } }
        .task(id: loadKey) {
            guard let show else { room?.stop(); room?.mechanism.motion.stop(); room = nil; return }
            if room == nil { room = ListeningRoomCoordinator(context: context, catalogService: catalogService, playbackFactory: playbackFactory) }
            room?.setActive(isActive)
            await room?.load(show: show)
        }
        .onChange(of: isActive) { _, active in
            room?.setActive(active)
            if active, let show { Task { await room?.load(show: show) } }
        }
        .onChange(of: CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID) { _, id in selectedShowID = id }
        .onChange(of: selectedShowID) { _, id in
            guard let id else { return }
            do { try CurrentShowSelectionStore(modelContext: context).select(showID: id); try context.save() }
            catch { context.rollback() }
        }
        .onDisappear { room?.setActive(false) }
    }
}

struct ListeningRoomView: View {
    @Bindable var room: ListeningRoomCoordinator
    let shows: [Show]
    let show: Show
    let isActive: Bool
    @Binding var selectedShowID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: ListeningDisc?
    @State private var showsArtists = false
    @State private var stageScale: CGFloat = 1
    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSSpacing.sm) {
                    header.id("listeningTop").opacity(chromeOpacity).allowsHitTesting(chromeOpacity > 0.9)
                    catalogStatus.opacity(chromeOpacity).allowsHitTesting(chromeOpacity > 0.9)
                    let scale = min((proxy.size.width - BSSpacing.lg * 2) / room.mechanism.configuration.geometry.canvas.width, ListeningStyle.maximumStageScale)
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
                    nowPlaying
                    if !room.discs.isEmpty {
                        ListeningCabinetView(room: room, scale: stageScale) { detail = $0 }
                    }
                    if let notice = room.mechanism.notice {
                        Text(notice).font(BSFont.caption).foregroundStyle(BSColor.Stage.muted)
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.top, BSLayout.pageHeaderTopPadding)
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
        .coordinateSpace(name: "listeningRoom")
        .onPreferenceChange(ListeningFramesKey.self, perform: updateFrames)
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(item: $detail) { disc in ListeningDiscDetailView(room: room, disc: disc) }
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
    private var chromeOpacity: Double { max(0, 1 - room.mechanism.motion.lid.value * 2) }
    private var header: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Text(BSLocalization.text("当前现场")).font(.caption).foregroundStyle(BSColor.Stage.muted)
            HStack {
            Menu {
                ForEach(shows) { show in Button(show.name) { selectedShowID = show.id } }
            } label: {
                HStack { Text(show.name).font(BSFont.V3.title2).lineLimit(1); Image(systemName: "chevron.down").font(BSFont.V3.caption) }
            }
            Spacer()
            Button { showsArtists = true } label: { Image(systemName: "person.2").font(BSFont.body).frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget).background(BSColor.Stage.surfaceRaised, in: Circle()) }
                .accessibilityLabel(BSLocalization.text("艺人详情"))
            }
            Text([show.date.formatted(date: .abbreviated, time: .omitted), show.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(BSColor.Stage.muted)
            if show.endedAt != nil { Text(BSLocalization.text("已结束")).font(.caption) }
            if show.artists.count > 1 {
                Text(BSLocalization.text("整场") + " · " + String(show.artists.count) + " " + BSLocalization.text("位艺人")).font(.caption)
            }
        }
    }
    @ViewBuilder private var catalogStatus: some View {
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
    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            ListeningSongCardView(room: room) { showsArtists = true }
            HStack {
                if room.onlyArtistID != nil || room.mechanism.disc?.id != "preparation" {
                    Button(BSLocalization.text("回到整场")) { room.returnToWholeShow() }.font(.subheadline).frame(minHeight: 44)
                }
                Spacer()
                Menu { mechanicalActions } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel(BSLocalization.text("播放器操作"))
            }
        }.padding(.vertical, BSSpacing.sm)
            .overlay(alignment: .top) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
    }
    private var mechanicalActions: some View {
        Group {
            switch room.mechanism.position {
            case .seated:
                Button(BSLocalization.text("释放 CD")) { room.mechanism.releaseDisc() }.disabled(!room.mechanism.isOpen)
            case .released:
                Button(BSLocalization.text("取出 CD")) { room.mechanism.removeDisc() }
                Button(BSLocalization.text("卡紧 CD")) { room.mechanism.seatDisc() }.disabled(!room.mechanism.canSeat)
            case .removed:
                Button(BSLocalization.text("装入 CD")) { room.mechanism.insertDisc() }.disabled(!room.mechanism.isOpen)
                Button(BSLocalization.text("放回唱片柜")) { room.mechanism.returnDisc() }
            case .stored: EmptyView()
            }
            Button(room.mechanism.isOpen ? BSLocalization.text("合盖") : "OPEN") { room.perform(.open) }
        }.disabled(room.busy || room.mechanism.isReturning)
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
