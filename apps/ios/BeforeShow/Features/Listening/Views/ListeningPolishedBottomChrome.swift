import SwiftUI

/// Chrome-only playback intent. `preparing` is treated as active so the compact
/// playback control never flashes a paused state while a user-initiated track loads.
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

enum ListeningMiniPlayerArtworkImage {
    static func displayed(
        loaded: UIImage?,
        url: URL?,
        memoryImage: (URL) -> UIImage? = { ShowCoverImageCache.shared.memoryImage(for: $0) }
    ) -> UIImage? {
        if let loaded { return loaded }
        guard let url else { return nil }
        return memoryImage(url)
    }
}

enum ListeningBottomBarPresentation {
    static func showsMiniPlayer(selectedTab: BeforeShowTab, hasLoadedDisc: Bool) -> Bool {
        hasLoadedDisc && selectedTab != .listen
    }
}

enum ListeningBottomBarLayout {
    static let tabSize: CGFloat = 58
    static let gap: CGFloat = 10
    static let miniPlayerWidth: CGFloat = 216
    static let iconGroupWidth = tabSize * 3 + gap * 2
    static let playerGroupWidth = tabSize * 2 + miniPlayerWidth + gap * 2
}

/// The root navigation is intentionally always compact and icon-only.
/// SwiftUI's TabView owns destination state, while this detached chrome owns the
/// visible root controls. Liquid Glass itself performs the Listen
/// circle <-> compact-player morph inside the stable root-bar footprint.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    @State private var store = ListeningPlaybackChromeStore.shared

    private var room: ListeningRoomCoordinator? { store.room }
    private var track: ListeningDiscTrack? { room?.track }

    private var hasLoadedDisc: Bool {
        guard let room, track != nil else { return false }
        return room.mechanism.hasDisc
    }

    private var showsMiniPlayer: Bool {
        ListeningBottomBarPresentation.showsMiniPlayer(
            selectedTab: selectedTab,
            hasLoadedDisc: hasLoadedDisc
        )
    }

    var body: some View {
        ListeningLiquidGlassBottomChrome(
            selectedTab: $selectedTab,
            showsMiniPlayer: showsMiniPlayer,
            room: room,
            track: track
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BSSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.bottomBar")
    }
}

private struct ListeningLiquidGlassBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    let showsMiniPlayer: Bool
    let room: ListeningRoomCoordinator?
    let track: ListeningDiscTrack?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: ListeningBottomBarLayout.gap) {
            HStack(spacing: ListeningBottomBarLayout.gap) {
                glassTabButton(.current)

                if showsMiniPlayer, let room, let track {
                    ListeningCompactPlaybackControl(
                        room: room,
                        track: track,
                        onSelectListen: { selectedTab = .listen }
                    )
                    .frame(
                        width: ListeningBottomBarLayout.miniPlayerWidth,
                        height: ListeningBottomBarLayout.tabSize
                    )
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("listen", in: glassNamespace)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    .transition(reduceMotion ? .opacity.animation(.easeOut(duration: 0.16)) : .identity)
                } else {
                    glassListenButton
                        .glassEffectID("listen", in: glassNamespace)
                        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                        .transition(reduceMotion ? .opacity.animation(.easeOut(duration: 0.16)) : .identity)
                }

                glassTabButton(.footprints)
            }
            .frame(
                width: showsMiniPlayer
                    ? ListeningBottomBarLayout.playerGroupWidth
                    : ListeningBottomBarLayout.iconGroupWidth
            )
        }
        .frame(height: ListeningBottomBarLayout.tabSize)
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
            value: showsMiniPlayer
        )
    }

    @ViewBuilder
    private func glassTabButton(_ tab: BeforeShowTab) -> some View {
        let isSelected = selectedTab == tab
        let button = Button {
            selectedTab = tab
        } label: {
            Image(systemName: tab.iconName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textSecondary)
                .frame(
                    width: ListeningBottomBarLayout.tabSize,
                    height: ListeningBottomBarLayout.tabSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .glassEffectID(glassID(for: tab), in: glassNamespace)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityIdentifier(tabAccessibilityIdentifier(tab))

        if isSelected {
            button.accessibilityAddTraits(.isSelected)
        } else {
            button
        }
    }

    private var glassListenButton: some View {
        let isSelected = selectedTab == .listen
        let button = Button {
            selectedTab = .listen
        } label: {
            Image(systemName: "opticaldisc")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textSecondary)
                .frame(
                    width: ListeningBottomBarLayout.tabSize,
                    height: ListeningBottomBarLayout.tabSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(BeforeShowTab.listen.localizedTitle)
        .accessibilityIdentifier("root.tab.listen")

        if isSelected {
            return AnyView(button.accessibilityAddTraits(.isSelected))
        }
        return AnyView(button)
    }

    private func glassID(for tab: BeforeShowTab) -> String {
        switch tab {
        case .current: return "current"
        case .listen: return "listen"
        case .footprints: return "footprints"
        }
    }
}

private struct ListeningCompactPlaybackControl: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let onSelectListen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkImage: UIImage?
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 128.0

    private var playerPhase: ListeningPlayerPhase { room.display.player.phase }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: playerPhase)
    }
    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.mechanism.disc?.artworkURL
        )
    }
    private var displayedArtwork: UIImage? {
        ListeningMiniPlayerArtworkImage.displayed(loaded: artworkImage, url: artworkURL)
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !showsPlayingState
            )
        ) { timeline in
            HStack(spacing: 6) {
                Button(action: onSelectListen) {
                    HStack(spacing: 9) {
                        ListeningArtworkDisc(
                            artwork: displayedArtwork,
                            angle: discAngle(at: timeline.date),
                            size: 34,
                            isPlaying: showsPlayingState
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(BSColor.textPrimary)
                                .lineLimit(1)

                            Text(track.artistName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(BSColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, minHeight: ListeningBottomBarLayout.tabSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(track.title)，\(track.artistName)")
                .accessibilityHint(BSLocalization.text("返回听"))
                .accessibilityIdentifier("listening.miniPlayer.openListen")

                Button {
                    room.perform(.playPause)
                } label: {
                    Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BSColor.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(
                            width: BSLayout.minTouchTarget,
                            height: BSLayout.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.88))
                .padding(.trailing, 4)
                .disabled(room.busy)
                .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
                .accessibilityIdentifier("listening.miniPlayer.playPause")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.compact")
        .task(id: artworkURL) {
            guard let artworkURL else {
                artworkImage = nil
                return
            }
            if let cached = ShowCoverImageCache.shared.memoryImage(for: artworkURL) {
                artworkImage = cached
                return
            }
            let loaded = await ShowCoverImageCache.shared.image(from: artworkURL)
            guard !Task.isCancelled else { return }
            artworkImage = loaded
        }
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

private struct ListeningArtworkDisc: View {
    let artwork: UIImage?
    let angle: Double
    let size: CGFloat
    var isPlaying: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BSColor.Stage.surface)

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .transaction { $0.animation = nil }
            } else {
                fallbackArtwork
            }

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                .frame(width: size * 0.48, height: size * 0.48)

            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.16),
                    BSColor.Accent.info.opacity(0.12),
                    Color.clear,
                    BSColor.Accent.violet.opacity(0.14),
                    Color.clear,
                    Color.white.opacity(0.18),
                    Color.clear
                ]),
                center: .center,
                angle: .degrees(-angle * 0.35)
            )
            .blendMode(.screen)

            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.22)

            Circle()
                .stroke(Color.white.opacity(0.60), lineWidth: 0.6)
                .frame(width: size * 0.12, height: size * 0.12)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .transaction { $0.animation = nil }
        .overlay(
            Circle()
                .stroke(
                    isPlaying ? BSColor.Accent.info.opacity(0.45) : BSColor.borderProminent,
                    lineWidth: 0.8
                )
        )
        .rotationEffect(.degrees(angle))
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

private func tabAccessibilityIdentifier(_ tab: BeforeShowTab) -> String {
    switch tab {
    case .current: return "root.tab.current"
    case .listen: return "root.tab.listen"
    case .footprints: return "root.tab.footprints"
    }
}
