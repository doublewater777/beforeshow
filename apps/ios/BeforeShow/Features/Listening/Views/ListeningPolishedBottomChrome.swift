import SwiftUI

/// Chrome-only playback intent. `preparing` is treated as an active playback
/// presentation so the mini player does not flash a paused/play state while a
/// user-initiated song is still loading.
enum ListeningMiniPlayerPlaybackAppearance {
    static func showsPlayingState(for phase: ListeningPlayerPhase) -> Bool {
        switch phase {
        case .preparing, .playing:
            return true
        case .noDisc, .paused, .stopped, .finished, .failed:
            return false
        }
    }

    static func statusText(for player: ListeningPlayerPresentation) -> String {
        switch player.phase {
        case .preparing, .playing:
            return BSLocalization.text("播放中")
        case .paused:
            return BSLocalization.text("暂停")
        case .noDisc, .stopped, .finished, .failed:
            return player.statusText
        }
    }
}

enum ListeningMiniPlayerArtworkSource {
    static func resolve(trackArtworkURL: URL?, discArtworkURL: URL?) -> URL? {
        discArtworkURL ?? trackArtworkURL
    }
}

struct ListeningPolishedBottomChrome: View {
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
    private var playerPhase: ListeningPlayerPhase {
        room?.display.player.phase ?? .noDisc
    }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: playerPhase)
    }
    private var mode: ListeningBottomChromeMode {
        .resolve(selectedTab: selectedTab, hasLoadedDisc: hasLoadedDisc)
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !showsPlayingState
            )
        ) { timeline in
            VStack(spacing: 8) {
                if mode == .fullPlayer, let room, let track = room.track {
                    ListeningPolishedFullMiniPlayer(
                        room: room,
                        track: track,
                        discAngle: discAngle(at: timeline.date),
                        currentDate: timeline.date,
                        namespace: playerNamespace
                    )
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if mode == .compactPlayer, let room, let track = room.track {
                    ListeningPolishedCompactMiniPlayer(
                        room: room,
                        track: track,
                        discAngle: discAngle(at: timeline.date),
                        currentDate: timeline.date,
                        namespace: playerNamespace,
                        onSelectListen: {
                            selectTab(.listen)
                        }
                    )
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ListeningPolishedTabBar(selectedTab: $selectedTab)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.88),
            value: mode
        )
        .onChange(of: showsPlayingState, initial: true) { wasPlaying, nowPlaying in
            let now = Date()
            if wasPlaying && !nowPlaying {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if !wasPlaying && nowPlaying {
                spinAnchor = now
            }
        }
        .onChange(of: reduceMotion) { wasReduced, isReduced in
            let now = Date()
            if !wasReduced && isReduced && showsPlayingState {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if wasReduced && !isReduced && showsPlayingState {
                spinAnchor = now
            }
        }
    }

    private func selectTab(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.88)) {
                selectedTab = tab
            }
        }
    }

    private func runningDiscAngle(at date: Date) -> Double {
        (frozenDiscAngle + date.timeIntervalSince(spinAnchor) * spinDegreesPerSecond)
            .truncatingRemainder(dividingBy: 360)
    }

    private func discAngle(at date: Date) -> Double {
        guard showsPlayingState, !reduceMotion else { return frozenDiscAngle }
        return runningDiscAngle(at: date)
    }
}

private struct ListeningPolishedFullMiniPlayer: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let discAngle: Double
    let currentDate: Date
    let namespace: Namespace.ID

    private var player: ListeningPlayerPresentation { room.display.player }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: player.phase)
    }
    private var trackNumber: String { String(format: "%02d", room.trackIndex + 1) }
    private var statusText: String {
        ListeningMiniPlayerPlaybackAppearance.statusText(for: player)
    }
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
                size: 48,
                isPlaying: showsPlayingState
            )
            .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.disc", in: namespace)

            VStack(alignment: .leading, spacing: 5) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("TR \(trackNumber)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(BSColor.Accent.info.opacity(0.95))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(BSColor.Accent.info.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.dim)

                    Text(track.artistName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.dim)

                    if showsPlayingState {
                        ListeningMiniEqualizerBars(
                            isPlaying: true,
                            currentDate: currentDate
                        )
                    }

                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(showsPlayingState ? BSColor.Accent.info : BSColor.Stage.muted)
                        .lineLimit(1)
                }

                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))

                            Capsule()
                                .fill(BSColor.brandGradientSoft)
                                .frame(width: max(3, proxy.size.width * progress))

                            if showsPlayingState && progress > 0.02 {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 4, height: 4)
                                    .shadow(color: BSColor.Accent.info, radius: 2)
                                    .offset(x: max(0, proxy.size.width * progress - 2))
                            }
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 1)
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
            .accessibilityLabel(BSLocalization.text(lidIsOpen ? "关闭 CD 盖" : "打开 CD 盖"))
            .accessibilityIdentifier("listening.miniPlayer.open")

            Button { room.perform(.playPause) } label: {
                ZStack {
                    Circle()
                        .fill(
                            showsPlayingState
                                ? LinearGradient(
                                    colors: [
                                        BSColor.Accent.info.opacity(0.30),
                                        BSColor.Accent.info.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.14),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                    Circle()
                        .strokeBorder(
                            showsPlayingState ? BSColor.Accent.info.opacity(0.45) : Color.white.opacity(0.20),
                            lineWidth: 1
                        )
                    Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BSColor.Accent.info)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 44, height: 44)
                .shadow(color: showsPlayingState ? BSColor.Accent.info.opacity(0.30) : Color.clear, radius: 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.playPause")
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background {
            ListeningPolishedPlayerSurface(cornerRadius: 24, accentGlow: showsPlayingState)
                .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.surface", in: namespace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.full")
    }
}

private struct ListeningPolishedCompactMiniPlayer: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let discAngle: Double
    let currentDate: Date
    let namespace: Namespace.ID
    let onSelectListen: () -> Void

    private var player: ListeningPlayerPresentation { room.display.player }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: player.phase)
    }
    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.mechanism.disc?.artworkURL
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onSelectListen()
            } label: {
                HStack(spacing: 10) {
                    ListeningArtworkDisc(
                        artworkURL: artworkURL,
                        angle: discAngle,
                        size: 38,
                        isPlaying: showsPlayingState
                    )
                    .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.disc", in: namespace)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(track.artistName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(BSColor.Stage.muted)
                                .lineLimit(1)

                            if showsPlayingState {
                                ListeningMiniEqualizerBars(
                                    isPlaying: true,
                                    currentDate: currentDate,
                                    barCount: 3,
                                    maxHeight: 8.0
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compactAccessibilityLabel)
            .accessibilityHint(BSLocalization.text("返回听"))

            Button {
                room.perform(.playPause)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            showsPlayingState
                                ? LinearGradient(
                                    colors: [
                                        BSColor.Accent.info.opacity(0.30),
                                        BSColor.Accent.info.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.14),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                    Circle()
                        .strokeBorder(
                            showsPlayingState ? BSColor.Accent.info.opacity(0.45) : Color.white.opacity(0.20),
                            lineWidth: 1
                        )
                    Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BSColor.Accent.info)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 38, height: 38)
                .shadow(color: showsPlayingState ? BSColor.Accent.info.opacity(0.25) : Color.clear, radius: 6)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.playPause")
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background {
            ListeningPolishedPlayerSurface(cornerRadius: 20, accentGlow: showsPlayingState)
                .matchedGeometryEffect(id: "listeningPolishedMiniPlayer.surface", in: namespace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.compact")
    }

    private var compactAccessibilityLabel: String {
        let state = BSLocalization.text(showsPlayingState ? "正在播放" : "已暂停")
        return "\(BeforeShowTab.listen.localizedTitle)，\(state) \(track.title)，\(track.artistName)"
    }
}

private struct ListeningPolishedTabBar: View {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BeforeShowTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 49)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )

                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 0.5)
            }
            .padding(.bottom, -50)
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.customTabBar")
    }

    private func tabButton(_ tab: BeforeShowTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            select(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: isSelected)

                Text(tab.localizedTitle)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? BSColor.Accent.info : Color.white.opacity(0.50))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("root.tab.\(tab.id)")
    }

    private func select(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.88)) {
                selectedTab = tab
            }
        }
    }
}

private struct ListeningArtworkDisc: View {
    let artworkURL: URL?
    let angle: Double
    let size: CGFloat
    var isPlaying: Bool = false

    var body: some View {
        ZStack {
            if isPlaying {
                Circle()
                    .fill(BSColor.Accent.info.opacity(0.24))
                    .frame(width: size + 4, height: size + 4)
                    .blur(radius: 6)
            }

            Circle()
                .fill(BSColor.Stage.surface)

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

            // Realistic CD optical groove rings
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                .frame(width: size * 0.48, height: size * 0.48)

            // Holographic rainbow optical diffraction sheen
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.16),
                    Color.cyan.opacity(0.12),
                    Color.clear,
                    Color.purple.opacity(0.14),
                    Color.clear,
                    Color.white.opacity(0.18),
                    Color.clear
                ]),
                center: .center,
                angle: .degrees(-angle * 0.35)
            )
            .blendMode(.screen)

            // Center spindle
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.22)

            Circle()
                .stroke(Color.white.opacity(0.60), lineWidth: 0.7)
                .frame(width: size * 0.12, height: size * 0.12)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            BSColor.Accent.info.opacity(isPlaying ? 0.45 : 0.20),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .rotationEffect(.degrees(angle))
        .shadow(color: isPlaying ? BSColor.Accent.info.opacity(0.18) : Color.clear, radius: 8)
        .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private var fallbackArtwork: some View {
        ZStack {
            BSColor.Stage.surfaceRaised
            Image(systemName: "opticaldisc")
                .font(.system(size: size * 0.48, weight: .regular))
                .foregroundStyle(BSColor.Stage.muted)
        }
    }
}

private struct ListeningPolishedGlassSurface: View {
    let cornerRadius: CGFloat
    var accentGlow: Bool = false

    var body: some View {
        ZStack {
            // 1. Apple Ultra Thin Material blur base
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // 2. Luminous frosted glass wash (gives visible frosted depth over dark backgrounds)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.05),
                            Color(white: 0.12).opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 3. Top specular shine / glass reflection
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.45)
                    )
                )

            // 4. Precision glass rim light / light-catching beveled edge
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.08),
                            accentGlow ? BSColor.Accent.info.opacity(0.45) : Color.white.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        }
        .shadow(
            color: accentGlow ? BSColor.Accent.info.opacity(0.18) : Color.clear,
            radius: 16,
            y: 4
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)
    }
}

private struct ListeningPolishedPlayerSurface: View {
    let cornerRadius: CGFloat
    var accentGlow: Bool = false

    var body: some View {
        ListeningPolishedGlassSurface(
            cornerRadius: cornerRadius,
            accentGlow: accentGlow
        )
    }
}

private struct ListeningMiniEqualizerBars: View {
    let isPlaying: Bool
    var currentDate: Date = Date()
    var barCount: Int = 4
    var maxHeight: CGFloat = 11.0
    var color: Color = BSColor.Accent.info

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.8) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color,
                                color.opacity(0.75)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.0, height: height(for: index))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .shadow(color: color.opacity(0.45), radius: 2)
        .accessibilityHidden(true)
    }

    private func height(for index: Int) -> CGFloat {
        guard isPlaying else { return 3.0 }
        let t = currentDate.timeIntervalSinceReferenceDate
        let frequencies: [Double] = [8.5, 12.8, 6.9, 10.4]
        let phases: [Double] = [0.0, 1.8, 3.4, 0.9]
        let f = frequencies[index % frequencies.count]
        let p = phases[index % phases.count]
        let wave = (sin(t * f + p) + 1.0) / 2.0
        return 3.0 + CGFloat(wave) * (maxHeight - 3.0)
    }
}

private struct ListeningPolishedLidGlyph: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Disc tray well
            Circle()
                .stroke(
                    isOpen ? BSColor.Accent.info.opacity(0.75) : Color.white.opacity(0.28),
                    lineWidth: 1.2
                )
                .frame(width: 17, height: 17)

            // Center spindle dot
            Circle()
                .fill(isOpen ? BSColor.Accent.info : Color.white.opacity(0.55))
                .frame(width: 4, height: 4)

            // Hinged lid visor that flips open with spring
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 2.2)
                .rotationEffect(.degrees(isOpen ? -28 : 0), anchor: .leading)
                .offset(x: isOpen ? 1 : 0, y: isOpen ? -8 : -8)
        }
        .frame(width: 38, height: 38)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(isOpen ? 0.14 : 0.08),
                    Color.white.opacity(isOpen ? 0.05 : 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Circle()
        )
        .overlay(
            Circle()
                .stroke(
                    isOpen ? BSColor.Accent.info.opacity(0.40) : Color.white.opacity(0.18),
                    lineWidth: 1
                )
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
            value: isOpen
        )
    }
}


