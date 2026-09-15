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
        .animation(
            reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.91),
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
            .accessibilityLabel(BSLocalization.text(lidIsOpen ? "关闭 CD 盖" : "打开 CD 盖"))
            .accessibilityIdentifier("listening.miniPlayer.open")

            Button { room.perform(.playPause) } label: {
                Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BSColor.Accent.info)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
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
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
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
        let player = room.display.player
        let showsPlayingState = ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: player.phase)

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
                Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BSColor.Accent.info)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
        }
        .padding(.horizontal, 10)
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
        let playing = ListeningMiniPlayerPlaybackAppearance.showsPlayingState(
            for: room.display.player.phase
        )
        let state = BSLocalization.text(playing ? "正在播放" : "已暂停")
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

            Circle()
                .fill(Color.black.opacity(0.78))
                .frame(width: size * 0.22, height: size * 0.22)

            Circle()
                .stroke(Color.white.opacity(0.50), lineWidth: 0.6)
                .frame(width: size * 0.12, height: size * 0.12)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
        .rotationEffect(.degrees(angle))
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

private struct ListeningPolishedPlayerSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                BSColor.Stage.surfaceRaised.opacity(0.72),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 16, y: 7)
    }
}

private struct ListeningPolishedLidGlyph: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(BSColor.Stage.muted.opacity(0.72), lineWidth: 1.4)
                .frame(width: 18, height: 10)
                .offset(y: 4)

            Circle()
                .stroke(BSColor.Accent.info.opacity(0.72), lineWidth: 1.1)
                .frame(width: 6, height: 6)
                .offset(y: 4)

            Capsule()
                .fill(BSColor.Stage.foreground.opacity(0.78))
                .frame(width: 18, height: 1.5)
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: .leading)
                .offset(x: isOpen ? 1 : 0, y: isOpen ? -4 : -2)
        }
        .foregroundStyle(BSColor.Stage.foreground.opacity(0.82))
        .background(Color.white.opacity(0.035), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
        .animation(
            reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.86),
            value: isOpen
        )
    }
}
