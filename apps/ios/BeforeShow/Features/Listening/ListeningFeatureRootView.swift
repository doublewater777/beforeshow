import SwiftUI
import SwiftData

@MainActor
enum ListeningChromeBootstrapper {
    static func prepare(
        show: Show?,
        context: ModelContext,
        catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
        artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
            $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
        }
    ) async -> ListeningRoomCoordinator? {
        guard let show else {
            let cached = ListeningRoomCache.shared
            let published = ListeningPlaybackChromeStore.shared.room
            cached?.stop()
            cached?.mechanism.motion.stop()
            if let published, published !== cached {
                published.stop()
                published.mechanism.motion.stop()
            }
            ListeningRoomCache.shared = nil
            ListeningPlaybackChromeStore.shared.room = nil
            return nil
        }

        let room: ListeningRoomCoordinator
        let createdCandidate: Bool
        if let cached = ListeningRoomCache.shared {
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
        guard room.mechanism.hasDisc, room.track != nil else {
            ListeningPlaybackChromeStore.shared.room = nil
            if createdCandidate {
                room.mechanism.motion.stop()
            }
            return nil
        }

        // Publish a restored-disc candidate to the cache before suspension so Listen
        // can adopt this exact coordinator even if the user enters while hydration is
        // still running. Candidates without a restored disc never enter the cache.
        if createdCandidate {
            ListeningRoomCache.shared = room
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

        ListeningPlaybackChromeStore.shared.room = room
        return room
    }
}

struct ListeningRootChromeModifier: ViewModifier {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]

    private var currentShow: Show? {
        let id = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
        return shows.first { $0.id == id }
    }

    private var currentShowID: UUID? { currentShow?.id }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ListeningPolishedBottomChrome(selectedTab: $selectedTab)
            }
            .task(id: currentShowID) {
                _ = await ListeningChromeBootstrapper.prepare(
                    show: currentShow,
                    context: modelContext
                )
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
            .onAppear {
                if isActive { ListeningPlayerWarmup.prepareIfNeeded() }
            }
            .onChange(of: isActive) { _, active in
                if active { ListeningPlayerWarmup.prepareIfNeeded() }
            }
    }

    @ViewBuilder
    private var room: some View {
        #if DEBUG
        if let fixture {
            ListenRootView(
                isActive: isActive,
                catalogService: ListeningFixtureCatalog(scenario: fixture.scenario),
                artistSearchService: ListeningFixtureArtistSearch(),
                playbackFactory: { _ in ListeningFixturePlayer() }
            )
            .modelContainer(fixture.container)
            .task(id: fixture.seededDisc?.id ?? fixture.mosaicSeededDisc?.id) {
                let disc = fixture.seededDisc ?? fixture.mosaicSeededDisc
                guard let disc else { return }
                while !Task.isCancelled {
                    if let room = ListeningRoomCache.shared, room.show != nil {
                        room.seedDisc(disc)
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

// MARK: - Refined root chrome

/// The custom root chrome deliberately keeps the existing app/tab palette neutral.
/// Album artwork supplies the colorful motion; cyan remains only the familiar
/// selected/control accent instead of repainting the whole bottom bar.
enum ListeningMiniPlayerArtworkSource {
    static func resolve(trackArtworkURL: URL?, discArtworkURL: URL?) -> URL? {
        discArtworkURL ?? trackArtworkURL
    }
}

private struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerNamespace
    @State private var store = ListeningPlaybackChromeStore.shared
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 128.0

    private var room: ListeningRoomCoordinator? { store.room }
    private var hasLoadedDisc: Bool {
        guard let room else { return false }
        return room.mechanism.hasDisc && room.track != nil
    }
    private var isPlaying: Bool { room?.isPlaying == true }
    private var mode: ListeningBottomChromeMode {
        .resolve(selectedTab: selectedTab, hasLoadedDisc: hasLoadedDisc)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isPlaying)) { timeline in
            VStack(spacing: 7) {
                if mode == .fullPlayer, let room, let track = room.track {
                    ListeningPolishedFullMiniPlayer(
                        room: room,
                        track: track,
                        discAngle: discAngle(at: timeline.date),
                        namespace: playerNamespace
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ListeningPolishedTabBar(
                    selectedTab: $selectedTab,
                    room: room,
                    mode: mode,
                    discAngle: discAngle(at: timeline.date),
                    namespace: playerNamespace
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.91), value: mode)
        .onChange(of: isPlaying, initial: true) { wasPlaying, nowPlaying in
            let now = Date()
            if wasPlaying && !nowPlaying {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if !wasPlaying && nowPlaying {
                spinAnchor = now
            }
        }
        .onChange(of: reduceMotion) { wasReduced, isReduced in
            let now = Date()
            if !wasReduced && isReduced && isPlaying {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if wasReduced && !isReduced && isPlaying {
                spinAnchor = now
            }
        }
    }

    private func runningDiscAngle(at date: Date) -> Double {
        (frozenDiscAngle + date.timeIntervalSince(spinAnchor) * spinDegreesPerSecond)
            .truncatingRemainder(dividingBy: 360)
    }

    private func discAngle(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return frozenDiscAngle }
        return runningDiscAngle(at: date)
    }
}

private struct ListeningPolishedFullMiniPlayer: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let discAngle: Double
    let namespace: Namespace.ID

    private var trackNumber: String { String(format: "%02d", room.trackIndex + 1) }
    private var statusText: String { BSLocalization.text(room.isPlaying ? "播放中" : "暂停") }
    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.mechanism.disc?.artworkURL
        )
    }
    private var progress: Double? {
        guard let duration = track.duration, duration.isFinite, duration > 0 else { return nil }
        return min(max(room.elapsed / duration, 0), 1)
    }
    private var lidIsOpen: Bool {
        (room.mechanism.motion.lid.target ?? room.mechanism.motion.lid.value) > 0.5
    }

    var body: some View {
        HStack(spacing: 12) {
            ListeningArtworkDisc(
                artworkURL: artworkURL,
                angle: discAngle,
                size: 48
            )
            .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.disc", in: namespace)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)

                Text("TR \(trackNumber) · \(track.artistName) · \(statusText)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)

                if let progress {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(BSColor.brandGradientSoft)
                                    .frame(width: max(3, proxy.size.width * progress))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { room.perform(.open) } label: {
                ListeningPolishedLidGlyph(isOpen: lidIsOpen)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text("打开 CD 盖"))
            .accessibilityIdentifier("listening.miniPlayer.open")

            Button { room.perform(.playPause) } label: {
                Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BSColor.Accent.info)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(room.isPlaying ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.playPause")
        }
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background {
            ListeningPolishedPlayerSurface(cornerRadius: 24)
                .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.surface", in: namespace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.full")
    }
}

private struct ListeningPolishedTabBar: View {
    @Binding var selectedTab: BeforeShowTab
    let room: ListeningRoomCoordinator?
    let mode: ListeningBottomChromeMode
    let discAngle: Double
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            rootTab(.current)

            if mode == .compactPlayer, let room, let track = room.track {
                compactListenPlayer(room: room, track: track)
                    .frame(minWidth: 160, maxWidth: .infinity)
                    .layoutPriority(2)
            } else {
                rootTab(.listen)
            }

            rootTab(.footprints)
        }
        .padding(6)
        .frame(height: 66)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(
            BSColor.Stage.surfaceRaised.opacity(0.76),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .accessibilityIdentifier("root.customTabBar")
    }

    private func rootTab(_ tab: BeforeShowTab) -> some View {
        let selected = selectedTab == tab

        return Button { select(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: .medium))
                Text(tab.localizedTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? BSColor.Accent.info : BSColor.Stage.muted)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("root.tab.\(tab.id)")
    }

    private func compactListenPlayer(
        room: ListeningRoomCoordinator,
        track: ListeningDiscTrack
    ) -> some View {
        let artworkURL = ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.mechanism.disc?.artworkURL
        )

        return HStack(spacing: 8) {
            Button { select(.listen) } label: {
                HStack(spacing: 8) {
                    ListeningArtworkDisc(
                        artworkURL: artworkURL,
                        angle: discAngle,
                        size: 36
                    )
                    .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.disc", in: namespace)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compactAccessibilityLabel(room: room, track: track))
            .accessibilityHint(BSLocalization.text("返回听"))

            Button { room.perform(.playPause) } label: {
                Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BSColor.Accent.info)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(room.isPlaying ? "暂停" : "播放"))
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background {
            ListeningPolishedPlayerSurface(cornerRadius: 20)
                .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.surface", in: namespace)
        }
        .accessibilityIdentifier("listening.miniPlayer.compact")
    }

    private func compactAccessibilityLabel(
        room: ListeningRoomCoordinator,
        track: ListeningDiscTrack
    ) -> String {
        let state = BSLocalization.text(room.isPlaying ? "正在播放" : "已暂停")
        return "\(BeforeShowTab.listen.localizedTitle)，\(state) \(track.title)，\(track.artistName)"
    }

    private func select(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.91)) {
                selectedTab = tab
            }
        }
    }
}

private struct ListeningArtworkDisc: View {
    let artworkURL: URL?
    let angle: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            artwork
                .frame(width: size, height: size)
                .clipShape(Circle())

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)

            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: size * 0.22, height: size * 0.22)

            Circle()
                .stroke(Color.white.opacity(0.56), lineWidth: 0.7)
                .frame(width: size * 0.13, height: size * 0.13)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .shadow(color: Color.black.opacity(0.30), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "opticaldisc")
                .font(.system(size: size * 0.42, weight: .light))
                .foregroundStyle(BSColor.Stage.muted)
        }
    }
}

private struct ListeningPolishedPlayerSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                BSColor.Stage.surfaceRaised.opacity(0.86),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
    }
}

private struct ListeningPolishedLidGlyph: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(BSColor.Stage.muted, lineWidth: 1.35)
                .frame(width: 18, height: 10)
                .offset(y: 4)

            Circle()
                .stroke(BSColor.Stage.muted.opacity(0.9), lineWidth: 1)
                .frame(width: 6, height: 6)
                .offset(y: 4)

            Capsule()
                .fill(BSColor.Stage.foreground.opacity(0.78))
                .frame(width: 18, height: 1.5)
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: .leading)
                .offset(x: isOpen ? 1 : 0, y: isOpen ? -4 : -2)
        }
        .background(Color.white.opacity(0.035), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.86), value: isOpen)
    }
}
