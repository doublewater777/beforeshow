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
}

/// Root navigation chrome. The middle Listen destination owns playback chrome:
/// it is a simple tab icon with no disc (or while Listen is selected), and expands
/// into the compact player on Current / Footprints when a disc is loaded.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
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

                Group {
                    if showsMiniPlayer, let room, let track {
                        ListeningCompactPlayerTab(
                            room: room,
                            track: track,
                            onSelectListen: { selectedTab = .listen }
                        )
                    } else {
                        tabButton(.listen)
                    }
                }
                .frame(width: showsMiniPlayer ? nil : ListeningBottomBarLayout.tabSize)
                .frame(maxWidth: showsMiniPlayer ? .infinity : nil)

                tabButton(.footprints)
            }
            .frame(maxWidth: showsMiniPlayer ? .infinity : nil)
        }
        .frame(maxWidth: ListeningBottomBarLayout.playerGroupMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BSSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.bottomBar")
        .task(id: selectedTab) {
            // Let TabView commit the destination first. Chrome follows on the next
            // main-actor turn without a competing layout/matched-geometry animation.
            await Task.yield()
            guard !Task.isCancelled else { return }
            presentedTab = selectedTab
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

private struct ListeningCompactPlayerTab: View {
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
            HStack(spacing: BSSpacing.xs) {
                Button(action: onSelectListen) {
                    HStack(spacing: BSSpacing.sm) {
                        ListeningArtworkDisc(
                            artwork: displayedArtwork,
                            angle: discAngle(at: timeline.date),
                            size: 34,
                            isPlaying: showsPlayingState
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(BSFont.caption)
                                .foregroundStyle(BSColor.textPrimary)
                                .lineLimit(1)

                            Text(track.artistName)
                                .font(BSFont.V3.caption)
                                .foregroundStyle(BSColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, BSSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
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
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.88))
                .disabled(room.busy)
                .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
                .accessibilityIdentifier("listening.miniPlayer.playPause")
            }
        }
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)

            if showsPlayingState {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(BSColor.Accent.info.opacity(0.08))
            }

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    showsPlayingState
                        ? BSColor.Accent.info.opacity(0.24)
                        : BSColor.borderProminent,
                    lineWidth: 0.8
                )
        }
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
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
