@MainActor enum ListeningRoomCache {
    static var shared: ListeningRoomCoordinator?
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
                        if !room.browseArtists.isEmpty,
                           !room.libraryDiscs.isEmpty || room.access.authorizationStatus == .authorized {
                            ListeningCabinetView(room: room, scale: scale, showAll: { showsCabinet = true }) {
                                room.browser.open($0)
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
                            Text(notice)
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("listening.mechanismNotice")
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
                room.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            playbackModeBadge
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(BSColor.Stage.foreground)
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
        .padding(.bottom, BSSpacing.sm)
        .zIndex(1)
    }

    private var playbackModeBadge: some View {
        let mode = room.display.roomMode
        return HStack(spacing: 5) {
            if mode == .connecting {
                ProgressView()
                    .tint(BSColor.Stage.accent)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: modeIcon(mode))
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(mode.title)
                .font(.system(size: 12, weight: mode == .fullPlayback ? .semibold : .medium))
        }
        .foregroundStyle(mode == .fullPlayback ? BSColor.Stage.accent : BSColor.Stage.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            mode == .fullPlayback ? BSColor.Stage.accent.opacity(0.12) : Color.white.opacity(0.06),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                mode == .fullPlayback ? BSColor.Stage.accent.opacity(0.3) : BSColor.Stage.border,
                lineWidth: 0.75
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("listening.playbackMode")
    }

    private func modeIcon(_ mode: ListeningRoomPlaybackMode) -> String {
        switch mode {
        case .connecting: "hourglass"
        case .fullPlayback: "apple.logo"
        case .preview: "waveform"
        case .metadataOnly: "list.bullet.rectangle"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if room.isAuthorizing {
            EmptyView()
        } else if room.access.authorizationStatus != .authorized {
            authorizationStatus
        } else {
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
                status("暂时无法更新专场唱片", action: room.display.recoveryAction)

            case .fatalUnavailable:
                status("暂时无法载入音乐", action: room.display.recoveryAction)

            case .needsAuthorization, .noCurrentShow, .ready:
                EmptyView()
            }
        }
    }

    private var authorizationStatus: some View {
        let recovery = room.display.recoveryAction
        return HStack(spacing: BSSpacing.sm) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let recovery {
                Button(recovery.title) {
                    room.performListeningRecovery(recovery)
                }
                .font(BSFont.caption.weight(.semibold))
                .foregroundStyle(recovery == .authorize ? Color.black : BSColor.Stage.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    recovery == .authorize ? BSColor.Stage.accent : BSColor.Stage.surfaceRaised,
                    in: Capsule()
                )
                .overlay {
                    if recovery != .authorize {
                        Capsule().stroke(BSColor.Stage.border, lineWidth: 1)
                    }
                }
            }
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func status(_ title: String, action: ListeningRecoveryAction?) -> some View {
        HStack {
            Text(BSLocalization.text(title))
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.muted)
            Spacer()
            if let action {
                Button(action.title) {
                    room.performListeningRecovery(action)
                }
                .font(BSFont.caption)
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
        room.mechanism.cabinetSlots = newSlots
        room.mechanism.cabinetScale = newCabinetScale
        if let frame = frames["cabinet"] {
            let origin = convert(frame.origin)
            room.mechanism.cabinetDropZone = CGRect(
                x: origin.x,
                y: origin.y,
                width: frame.width / stageScale,
                height: frame.height / stageScale / cosine
            )
        }
    }
}
