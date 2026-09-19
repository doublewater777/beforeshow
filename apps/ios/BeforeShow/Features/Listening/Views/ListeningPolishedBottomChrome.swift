import SwiftUI

/// Chrome-only playback intent. `preparing` is treated as an active playback
/// presentation so the compact player does not flash a paused/play state while a
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
    static let playerGroupMaxWidth: CGFloat = 352
    static let miniPlayerWidth = playerGroupMaxWidth - tabSize * 2 - gap * 2
    static let iconGroupWidth = tabSize * 3 + gap * 2
    static let transitionDelay = Duration.milliseconds(45)
    static let transitionDuration = 0.34
}

/// Root navigation chrome. The middle Listen destination owns playback chrome:
/// it is a simple tab icon with no disc (or while Listen is selected), and expands
/// into the compact player on Current / Footprints when a disc is loaded.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedTab: BeforeShowTab
    @State private var store = ListeningPlaybackChromeStore.shared

    init(selectedTab: Binding<BeforeShowTab>) {
        self._selectedTab = selectedTab
        self._presentedTab = State(initialValue: selectedTab.wrappedValue)
    }

    private var room: ListeningRoomCoordinator? { store.room }
    private var track: ListeningDiscTrack? { room?.track }
    private var hasLoadedDisc: Bool {
        guard let room, track != nil else { return false }
        return room.mechanism.hasDisc
    }
    private var showsMiniPlayer: Bool {
        ListeningBottomBarPresentation.showsMiniPlayer(
            selectedTab: presentedTab,
            hasLoadedDisc: hasLoadedDisc
        )
    }

    var body: some View {
        ZStack {
            HStack(spacing: ListeningBottomBarLayout.gap) {
                tabButton(.current)

                ListeningMorphingListenControl(
                    expanded: showsMiniPlayer,
                    isSelected: selectedTab == .listen,
                    room: room,
                    track: track,
                    onSelectListen: { selectedTab = .listen }
                )
                .frame(
                    width: showsMiniPlayer
                        ? ListeningBottomBarLayout.miniPlayerWidth
                        : ListeningBottomBarLayout.tabSize
                )

                tabButton(.footprints)
            }
            .frame(
                width: showsMiniPlayer
                    ? ListeningBottomBarLayout.playerGroupMaxWidth
                    : ListeningBottomBarLayout.iconGroupWidth
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BSSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.bottomBar")
        .task(id: selectedTab) {
            // TabView owns the selection frame. The persistent Listen control then
            // morphs independently, so page navigation never shares its layout work.
            await Task.yield()
            guard !Task.isCancelled else { return }

            if reduceMotion {
                presentedTab = selectedTab
                return
            }

            try? await Task.sleep(for: ListeningBottomBarLayout.transitionDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: ListeningBottomBarLayout.transitionDuration)) {
                presentedTab = selectedTab
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: BeforeShowTab) -> some View {
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
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                    if isSelected {
                        Circle()
                            .fill(BSColor.Stage.accent.opacity(0.16))
                    }
                    Circle()
                        .stroke(
                            isSelected
                                ? BSColor.Stage.accent.opacity(0.34)
                                : BSColor.borderProminent,
                            lineWidth: 0.8
                        )
                }
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityIdentifier(tabAccessibilityIdentifier(tab))

        if isSelected {
            button.accessibilityAddTraits(.isSelected)
        } else {
            button
        }
    }

    private func tabAccessibilityIdentifier(_ tab: BeforeShowTab) -> String {
        switch tab {
        case .current: return "root.tab.current"
        case .listen: return "root.tab.listen"
        case .footprints: return "root.tab.footprints"
        }
    }
}

private struct ListeningMorphingListenControl: View {
    let expanded: Bool
    let isSelected: Bool
    @Bindable var room: ListeningRoomCoordinator?
    let track: ListeningDiscTrack?
    let onSelectListen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkImage: UIImage?
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 128.0
    private let collapsedHeight: CGFloat = 58
    private let expandedHeight: CGFloat = 52
    private let artworkSize: CGFloat = 34

    private var playerPhase: ListeningPlayerPhase {
        room?.display.player.phase ?? .noDisc
    }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: playerPhase)
    }
    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track?.artworkURL,
            discArtworkURL: room?.mechanism.disc?.artworkURL
        )
    }
    private var displayedArtwork: UIImage? {
        ListeningMiniPlayerArtworkImage.displayed(loaded: artworkImage, url: artworkURL)
    }
    private var controlHeight: CGFloat {
        expanded ? expandedHeight : collapsedHeight
    }
    private var cornerRadius: CGFloat {
        expanded ? 24 : collapsedHeight / 2
    }
    private var artworkOffset: CGFloat {
        expanded ? -(ListeningBottomBarLayout.miniPlayerWidth / 2 - 29) : 0
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !showsPlayingState
            )
        ) { timeline in
            ZStack {
                selectSurface

                ListeningArtworkDisc(
                    artwork: displayedArtwork,
                    angle: discAngle(at: timeline.date),
                    size: artworkSize,
                    isPlaying: showsPlayingState
                )
                .offset(x: artworkOffset)
                .allowsHitTesting(false)

                trackMetadata
                    .offset(x: 5)
                    .allowsHitTesting(false)

                if let room {
                    playPauseButton(room: room)
                        .offset(x: ListeningBottomBarLayout.miniPlayerWidth / 2 - 30)
                }
            }
        }
        .frame(height: controlHeight)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BSColor.Stage.accent.opacity(0.16))
            } else if showsPlayingState {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BSColor.Accent.info.opacity(0.08))
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected
                        ? BSColor.Stage.accent.opacity(0.34)
                        : (showsPlayingState
                            ? BSColor.Accent.info.opacity(0.24)
                            : BSColor.borderProminent),
                    lineWidth: 0.8
                )
        }
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    @ViewBuilder
    private var selectSurface: some View {
        let button = Button(action: onSelectListen) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            expanded && track != nil
                ? "\(track?.title ?? "")，\(track?.artistName ?? "")"
                : BeforeShowTab.listen.localizedTitle
        )
        .accessibilityHint(expanded ? BSLocalization.text("返回听") : "")
        .accessibilityIdentifier(
            expanded ? "listening.miniPlayer.openListen" : "root.tab.listen"
        )

        if isSelected {
            button.accessibilityAddTraits(.isSelected)
        } else {
            button
        }
    }

    private var trackMetadata: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track?.title ?? "")
                .font(BSFont.caption)
                .foregroundStyle(BSColor.textPrimary)
                .lineLimit(1)

            Text(track?.artistName ?? "")
                .font(BSFont.V3.caption)
                .foregroundStyle(BSColor.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 108, alignment: .leading)
        .mask(
            Rectangle()
                .scaleEffect(x: expanded ? 1 : 0.02, anchor: .leading)
        )
        .opacity(expanded ? 1 : 0)
        .scaleEffect(expanded ? 1 : 0.97, anchor: .leading)
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.18).delay(expanded ? 0.07 : 0),
            value: expanded
        )
    }

    @ViewBuilder
    private func playPauseButton(room: ListeningRoomCoordinator) -> some View {
        Button {
            room.perform(.playPause)
        } label: {
            Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BSColor.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.88))
        .disabled(room.busy || !expanded)
        .opacity(expanded ? 1 : 0)
        .scaleEffect(expanded ? 1 : 0.82)
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.16).delay(expanded ? 0.13 : 0),
            value: expanded
        )
        .accessibilityHidden(!expanded)
        .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
        .accessibilityIdentifier("listening.miniPlayer.playPause")
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
