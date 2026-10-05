import SwiftUI

/// Chrome renders the unified playback projection instead of guessing from
/// transport truth or a command timeout.
enum ListeningMiniPlayerPlaybackAppearance {
    static func showsPlayingState(for phase: ListeningPlayerPhase) -> Bool {
        phase.isPlaybackActive
    }

    static func statusText(for player: ListeningPlayerPresentation) -> String {
        switch player.phase {
        case .preparing, .waiting, .playing, .seeking:
            return BSLocalization.text("播放中")
        case .paused, .interrupted:
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

enum ListeningMiniPlayerSwipeAction: Equatable {
    case previous
    case next
}

enum ListeningMiniPlayerSwipeIntent {
    static let activationDistance: CGFloat = 8
    static let commitDistance: CGFloat = 52
    static let projectedCommitDistance: CGFloat = 88
    static let horizontalDominanceRatio: CGFloat = 1.15
    static let pageTravel: CGFloat = 164
    static let unavailableEdgeResistance: CGFloat = 0.18

    static func isHorizontal(_ translation: CGSize) -> Bool {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        return horizontalDistance >= activationDistance
            && horizontalDistance > verticalDistance * horizontalDominanceRatio
    }

    static func action(
        for translation: CGSize,
        predictedEndTranslation: CGSize? = nil
    ) -> ListeningMiniPlayerSwipeAction? {
        guard isHorizontal(translation) else { return nil }

        let predicted = predictedEndTranslation ?? translation
        guard abs(translation.width) >= commitDistance
                || abs(predicted.width) >= projectedCommitDistance else {
            return nil
        }

        return translation.width < 0 ? .next : .previous
    }

    static func trackedOffset(for translation: CGSize, canNavigate: Bool) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }

        let maximumTravel = pageTravel * 1.06
        let direct = min(max(translation.width, -maximumTravel), maximumTravel)
        guard !canNavigate else { return direct }

        let resisted = direct * unavailableEdgeResistance
        return min(max(resisted, -18), 18)
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
        return room.hasLoadedDisc
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

private enum ListeningBottomBarGeometry {
    static func selectionOffset(
        for tab: BeforeShowTab,
        showsMiniPlayer: Bool
    ) -> CGFloat {
        let middleWidth = showsMiniPlayer
            ? ListeningBottomBarLayout.miniPlayerWidth
            : ListeningBottomBarLayout.tabSize
        let sideDistance =
            middleWidth / 2
            + ListeningBottomBarLayout.gap
            + ListeningBottomBarLayout.tabSize / 2

        switch tab {
        case .current:
            return -sideDistance
        case .listen:
            return 0
        case .footprints:
            return sideDistance
        }
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
            ZStack {
                selectionLens

                glassTabButton(.current)
                    .offset(
                        x: ListeningBottomBarGeometry.selectionOffset(
                            for: .current,
                            showsMiniPlayer: showsMiniPlayer
                        )
                    )
                    .animation(miniPlayerMorphAnimation, value: showsMiniPlayer)

                centerControl

                glassTabButton(.footprints)
                    .offset(
                        x: ListeningBottomBarGeometry.selectionOffset(
                            for: .footprints,
                            showsMiniPlayer: showsMiniPlayer
                        )
                    )
                    .animation(miniPlayerMorphAnimation, value: showsMiniPlayer)
            }
            .frame(
                width: ListeningBottomBarLayout.playerGroupWidth,
                height: ListeningBottomBarLayout.tabSize
            )
        }
        .frame(height: ListeningBottomBarLayout.tabSize)
    }

    private var centerControl: some View {
        ZStack {
            if showsMiniPlayer, let room, let track {
                ListeningCompactPlaybackControl(
                    room: room,
                    track: track,
                    isVisible: showsMiniPlayer,
                    onSelectListen: { selectTab(.listen) }
                )
                .transition(.opacity)
            } else {
                glassListenButton
                    .transition(.opacity)
            }
        }
        .animation(centerContentAnimation, value: showsMiniPlayer)
        .frame(
            width: showsMiniPlayer
                ? ListeningBottomBarLayout.miniPlayerWidth
                : ListeningBottomBarLayout.tabSize,
            height: ListeningBottomBarLayout.tabSize
        )
        .clipShape(Capsule())
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        .glassEffectID("listen", in: glassNamespace)
        .animation(miniPlayerMorphAnimation, value: showsMiniPlayer)
    }

    private var selectionLens: some View {
        Circle()
            .fill(BSColor.Stage.accent.opacity(0.16))
            .frame(
                width: ListeningBottomBarLayout.tabSize - 12,
                height: ListeningBottomBarLayout.tabSize - 12
            )
            .offset(
                x: ListeningBottomBarGeometry.selectionOffset(
                    for: selectedTab,
                    showsMiniPlayer: showsMiniPlayer
                )
            )
            .animation(miniPlayerMorphAnimation, value: selectedTab)
            .animation(miniPlayerMorphAnimation, value: showsMiniPlayer)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var miniPlayerMorphAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.28, dampingFraction: 0.90)
    }

    private var centerContentAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.16 : 0.10)
    }

    private func glassTabButton(_ tab: BeforeShowTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectTab(tab)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var glassListenButton: some View {
        let isSelected = selectedTab == .listen
        return Button {
            selectTab(.listen)
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
        .accessibilityLabel(BeforeShowTab.listen.localizedTitle)
        .accessibilityIdentifier("root.tab.listen")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectTab(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
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
    let isVisible: Bool
    let onSelectListen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkImage: UIImage?
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeSourceTrack: ListeningDiscTrack?
    @State private var swipePreviousTrack: ListeningDiscTrack?
    @State private var swipeNextTrack: ListeningDiscTrack?
    @State private var isCompletingSwipe = false
    @State private var swipeFeedbackCount = 0

    private let spinDegreesPerSecond = 128.0

    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(
            for: room.display.player.phase
        )
    }
    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.display.hardware.artworkURL
        )
    }
    private var displayedArtwork: UIImage? {
        ListeningMiniPlayerArtworkImage.displayed(loaded: artworkImage, url: artworkURL)
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !showsPlayingState || !isVisible
            )
        ) { timeline in
            HStack(spacing: 6) {
                ZStack {
                    if let previousTrack = pagingPreviousTrack {
                        trackPage(previousTrack, at: timeline.date)
                            .offset(
                                x: swipeOffset - ListeningMiniPlayerSwipeIntent.pageTravel
                            )
                    }

                    trackPage(pagingSourceTrack, at: timeline.date)
                        .offset(x: swipeOffset)

                    if let nextTrack = pagingNextTrack {
                        trackPage(nextTrack, at: timeline.date)
                            .offset(
                                x: swipeOffset + ListeningMiniPlayerSwipeIntent.pageTravel
                            )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: ListeningBottomBarLayout.tabSize)
                .contentShape(Rectangle())
                .clipped()
                .onTapGesture {
                    guard !isCompletingSwipe else { return }
                    onSelectListen()
                }
                .gesture(trackSwipeGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(track.title)，\(track.artistName)")
                .accessibilityHint(BSLocalization.text("返回听"))
                .accessibilityAction {
                    guard !isCompletingSwipe else { return }
                    onSelectListen()
                }
                .accessibilityIdentifier("listening.miniPlayer.openListen")

                Button {
                    room.perform(.playPause)
                } label: {
                    Image(systemName: room.display.player.showsPauseControl ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BSColor.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(
                            width: BSLayout.minTouchTarget,
                            height: BSLayout.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.96))
                .padding(.trailing, 4)
                .disabled(isCompletingSwipe || !room.display.player.canPlayPause)
                .accessibilityLabel(BSLocalization.text(
                    room.display.player.showsPauseControl ? "暂停" : "播放"
                ))
                .accessibilityIdentifier("listening.miniPlayer.playPause")
            }
        }
        .sensoryFeedback(
            .impact(weight: .light, intensity: 0.7),
            trigger: swipeFeedbackCount
        )
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

    private var pagingSourceTrack: ListeningDiscTrack {
        swipeSourceTrack ?? track
    }

    private var pagingPreviousTrack: ListeningDiscTrack? {
        swipeSourceTrack == nil ? adjacentTrack(for: .previous) : swipePreviousTrack
    }

    private var pagingNextTrack: ListeningDiscTrack? {
        swipeSourceTrack == nil ? adjacentTrack(for: .next) : swipeNextTrack
    }

    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: ListeningMiniPlayerSwipeIntent.activationDistance)
            .onChanged { value in
                guard !room.busy, !isCompletingSwipe,
                      ListeningMiniPlayerSwipeIntent.isHorizontal(value.translation) else {
                    return
                }

                captureSwipeSnapshotIfNeeded()
                let action: ListeningMiniPlayerSwipeAction =
                    value.translation.width < 0 ? .next : .previous
                let canNavigate = destinationTrack(for: action) != nil

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    swipeOffset = ListeningMiniPlayerSwipeIntent.trackedOffset(
                        for: value.translation,
                        canNavigate: canNavigate
                    )
                }
            }
            .onEnded { value in
                guard !isCompletingSwipe else { return }

                let action = ListeningMiniPlayerSwipeIntent.action(
                    for: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                )
                guard !room.busy,
                      let action,
                      let destination = destinationTrack(for: action) else {
                    settleSwipeBack()
                    return
                }

                completeSwipe(action, destination: destination)
            }
    }

    @ViewBuilder
    private func trackPage(_ pageTrack: ListeningDiscTrack, at date: Date) -> some View {
        HStack(spacing: 9) {
            ListeningArtworkDisc(
                artwork: displayedArtwork(for: pageTrack),
                angle: discAngle(at: date),
                size: 34,
                isPlaying: showsPlayingState
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(pageTrack.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(BSColor.textPrimary)
                    .lineLimit(1)

                Text(pageTrack.artistName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(BSColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, minHeight: ListeningBottomBarLayout.tabSize)
        .allowsHitTesting(false)
    }

    private func displayedArtwork(for pageTrack: ListeningDiscTrack) -> UIImage? {
        let pageArtworkURL = ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: pageTrack.artworkURL,
            discArtworkURL: room.display.hardware.artworkURL
        )
        if pageArtworkURL == artworkURL {
            return displayedArtwork
        }
        return ListeningMiniPlayerArtworkImage.displayed(
            loaded: nil,
            url: pageArtworkURL
        )
    }

    private func adjacentTrack(for action: ListeningMiniPlayerSwipeAction) -> ListeningDiscTrack? {
        room.adjacentLoadedTrack(delta: action == .next ? 1 : -1)
    }

    private func captureSwipeSnapshotIfNeeded() {
        guard swipeSourceTrack == nil else { return }
        swipeSourceTrack = track
        swipePreviousTrack = adjacentTrack(for: .previous)
        swipeNextTrack = adjacentTrack(for: .next)
    }

    private func destinationTrack(for action: ListeningMiniPlayerSwipeAction) -> ListeningDiscTrack? {
        switch action {
        case .previous:
            return swipeSourceTrack == nil ? adjacentTrack(for: .previous) : swipePreviousTrack
        case .next:
            return swipeSourceTrack == nil ? adjacentTrack(for: .next) : swipeNextTrack
        }
    }

    private func completeSwipe(
        _ action: ListeningMiniPlayerSwipeAction,
        destination: ListeningDiscTrack
    ) {
        captureSwipeSnapshotIfNeeded()
        isCompletingSwipe = true

        swipeFeedbackCount += 1
        room.skip(action == .next ? 1 : -1)

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swipeOffset = action == .next
                    ? -ListeningMiniPlayerSwipeIntent.pageTravel
                    : ListeningMiniPlayerSwipeIntent.pageTravel
            }
            waitForTrackChange(to: destination.id)
            return
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04), completionCriteria: .logicallyComplete) {
            swipeOffset = action == .next
                ? -ListeningMiniPlayerSwipeIntent.pageTravel
                : ListeningMiniPlayerSwipeIntent.pageTravel
        } completion: {
            waitForTrackChange(to: destination.id)
        }
    }

    private func settleSwipeBack() {
        guard swipeSourceTrack != nil || swipeOffset != 0 else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.86)) {
            swipeOffset = 0
        } completion: {
            resetSwipePresentation()
        }
    }

    private func waitForTrackChange(to destinationID: String) {
        if room.track?.id == destinationID {
            resetSwipePresentation()
            return
        }

        Task { @MainActor in
            for _ in 0..<30 {
                guard isCompletingSwipe else { return }
                if room.track?.id == destinationID {
                    resetSwipePresentation()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }

            if room.track?.id == destinationID {
                resetSwipePresentation()
            } else {
                settleSwipeBack()
                isCompletingSwipe = false
            }
        }
    }

    private func resetSwipePresentation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            swipeOffset = 0
            swipeSourceTrack = nil
            swipePreviousTrack = nil
            swipeNextTrack = nil
            isCompletingSwipe = false
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
        .drawingGroup()
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
