import SwiftUI

/// Chrome renders the unified playback projection instead of guessing from
/// transport truth or a command timeout.
enum ListeningMiniPlayerPlaybackAppearance {
    static func showsPlayingState(for phase: ListeningPlayerPhase) -> Bool {
        phase.isPlaybackActive
    }
}

enum ListeningMiniPlayerArtworkSource {
    static func resolve(trackArtworkURL: URL?, discArtworkURL: URL?) -> URL? {
        trackArtworkURL ?? discArtworkURL
    }
}

enum ListeningMiniPlayerArtworkImage {
    static func displayed(
        loaded: UIImage?,
        url: URL?,
        memoryImage: (URL) -> UIImage? = { ShowCoverImageCache.shared.persistedImage(for: $0) }
    ) -> UIImage? {
        if let loaded { return loaded }
        guard let url else { return nil }
        return memoryImage(url)
    }
}

enum ListeningBottomBarPresentation {
    enum Tap: Equatable { case open(ListeningSurface), nowPlaying, video }
    /// Off Listen the mini player leads back to its surface; on Listen it opens the full player.
    static func tap(selectedTab: BeforeShowTab, isVideo: Bool) -> Tap {
        guard selectedTab == .listen else { return .open(isVideo ? .watch : .listen) }
        return isVideo ? .video : .nowPlaying
    }
}

enum ListeningBottomBarLayout {
    static let tabSize: CGFloat = 58
    static let gap: CGFloat = 10
    static let miniPlayerWidth: CGFloat = 216
    static let playerGroupWidth = tabSize * 2 + miniPlayerWidth + gap * 2
}

/// The root navigation is intentionally compact: two icon tabs around a resident
/// mini player. SwiftUI's TabView owns destination state, while this detached
/// chrome owns the visible root controls.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    @State private var store = ListeningRoomSessionStore.shared

    private var room: ListeningRoomCoordinator? { store.chromeRoom }
    private var track: ListeningDiscTrack? { room?.track }

    private var hasLoadedDisc: Bool {
        guard let room, track != nil else { return false }
        return room.hasLoadedDisc
    }

    var body: some View {
        ListeningLiquidGlassBottomChrome(
            selectedTab: $selectedTab,
            room: hasLoadedDisc ? room : nil,
            track: track
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BSSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.bottomBar")
    }
}

enum ListeningBottomBarGeometry {
    static func selectionOffset(for tab: BeforeShowTab) -> CGFloat {
        let sideDistance = ListeningBottomBarLayout.miniPlayerWidth / 2
            + ListeningBottomBarLayout.gap + ListeningBottomBarLayout.tabSize / 2

        switch tab {
        case .current: return -sideDistance
        case .listen: return 0
        case .footprints: return sideDistance
        }
    }

    static func lensWidth(for tab: BeforeShowTab) -> CGFloat {
        switch tab {
        case .listen:
            return ListeningBottomBarLayout.miniPlayerWidth - 12
        case .current, .footprints:
            return ListeningBottomBarLayout.tabSize - 12
        }
    }
}

private struct ListeningLiquidGlassBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    /// Present only while a disc is loaded; otherwise the mini player rests empty.
    let room: ListeningRoomCoordinator?
    let track: ListeningDiscTrack?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        BSGlassEffectContainer(spacing: ListeningBottomBarLayout.gap) {
            ZStack {
                selectionLens

                glassTabButton(.current)
                    .offset(x: ListeningBottomBarGeometry.selectionOffset(for: .current))

                centerControl

                glassTabButton(.footprints)
                    .offset(x: ListeningBottomBarGeometry.selectionOffset(for: .footprints))
            }
            .frame(
                width: ListeningBottomBarLayout.playerGroupWidth,
                height: ListeningBottomBarLayout.tabSize
            )
        }
        .frame(height: ListeningBottomBarLayout.tabSize)
    }

    private var centerControl: some View {
        let isSelected = selectedTab == .listen
        return ZStack {
            if ListeningVideoDock.shared.hasVideo {
                ListeningVideoMiniPlayer(dock: .shared, isSelected: isSelected) { openMiniPlayer(isVideo: true) }
                    .transition(.opacity)
            } else if let room, let track {
                ListeningCompactPlaybackControl(
                    room: room,
                    track: track,
                    isSelected: isSelected,
                    onSelectListen: { openMiniPlayer(isVideo: false) }
                )
                .transition(.opacity)
            } else {
                ListeningEmptyMiniPlayer(isSelected: isSelected, onTap: openEmptyMiniPlayer)
                    .transition(.opacity)
            }
        }
        .animation(centerContentAnimation, value: track == nil)
        .frame(width: ListeningBottomBarLayout.miniPlayerWidth, height: ListeningBottomBarLayout.tabSize)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .bsGlass(in: Capsule())
        .bsGlassID("listen", in: glassNamespace)
    }

    private var selectionLens: some View {
        Capsule()
            .fill(BSColor.Stage.accent.opacity(0.18))
            .frame(
                width: ListeningBottomBarGeometry.lensWidth(for: selectedTab),
                height: ListeningBottomBarLayout.tabSize - 12
            )
            .offset(x: ListeningBottomBarGeometry.selectionOffset(for: selectedTab))
            .animation(miniPlayerMorphAnimation, value: selectedTab)
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
        .bsGlass(in: Circle())
        .bsGlassID(glassID(for: tab), in: glassNamespace)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityIdentifier(tabAccessibilityIdentifier(tab))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectTab(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
    }

    /// Nothing to resume: off Listen it leads there, on Listen it opens 「帮我挑一张」.
    private func openEmptyMiniPlayer() {
        if selectedTab == .listen {
            NotificationCenter.default.post(name: .listeningOpenPickDisc, object: nil)
        } else {
            ListeningRoomSessionStore.shared.surface = .listen
            selectTab(.listen)
        }
    }

    private func openMiniPlayer(isVideo: Bool) {
        switch ListeningBottomBarPresentation.tap(selectedTab: selectedTab, isVideo: isVideo) {
        case .open(let surface): ListeningRoomSessionStore.shared.surface = surface; selectTab(.listen)
        case .nowPlaying: ListeningRoomSessionStore.shared.isNowPlayingPresented = true
        case .video: ListeningVideoDock.shared.isExpanded = true
        }
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
    let isSelected: Bool
    let onSelectListen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkImage: UIImage?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeSourceTrack: ListeningDiscTrack?
    @State private var swipePreviousTrack: ListeningDiscTrack?
    @State private var swipeNextTrack: ListeningDiscTrack?
    @State private var isCompletingSwipe = false
    @State private var swipeFeedbackCount = 0

    init(
        room: ListeningRoomCoordinator,
        track: ListeningDiscTrack,
        isSelected: Bool = false,
        onSelectListen: @escaping () -> Void
    ) {
        self.room = room
        self.track = track
        self.isSelected = isSelected
        self.onSelectListen = onSelectListen
        let initialURL = ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.loadedDisc?.artworkURL
        )
        _artworkImage = State(
            initialValue: initialURL.flatMap {
                ShowCoverImageCache.shared.persistedImage(for: $0)
            }
        )
    }

    private var artworkURL: URL? {
        ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.loadedDisc?.artworkURL
        )
    }
    private var displayedArtwork: UIImage? {
        ListeningMiniPlayerArtworkImage.displayed(loaded: artworkImage, url: artworkURL)
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if let previousTrack = pagingPreviousTrack {
                    trackPage(previousTrack)
                        .offset(
                            x: swipeOffset - ListeningMiniPlayerSwipeIntent.pageTravel
                        )
                }

                trackPage(pagingSourceTrack)
                    .offset(x: swipeOffset)

                if let nextTrack = pagingNextTrack {
                    trackPage(nextTrack)
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
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(track.title)，\(track.artistName)")
            .accessibilityHint(BSLocalization.text("返回听"))
            .accessibilityAction {
                guard !isCompletingSwipe else { return }
                onSelectListen()
            }
            .accessibilityIdentifier("listening.miniPlayer.openListen")

            Button {
                room.playPause()
            } label: {
                Image(systemName: room.display.player.showsPauseControl ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textPrimary)
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
            if let cached = ShowCoverImageCache.shared.persistedImage(for: artworkURL) {
                artworkImage = cached
                return
            }
            let loaded = await ShowCoverImageCache.shared.image(from: artworkURL)
            guard !Task.isCancelled else { return }
            artworkImage = loaded
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
                guard !isCompletingSwipe,
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
                guard let action,
                      let destination = destinationTrack(for: action) else {
                    settleSwipeBack()
                    return
                }

                completeSwipe(action, destination: destination)
            }
    }

    @ViewBuilder
    private func trackPage(_ pageTrack: ListeningDiscTrack) -> some View {
        HStack(spacing: 9) {
            ListeningMiniArtwork(
                artwork: displayedArtwork(for: pageTrack),
                size: 34,
                isHighlighted: isSelected
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(pageTrack.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textPrimary)
                    .lineLimit(1)

                Text(pageTrack.artistName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? BSColor.textSecondary : BSColor.textTertiary)
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
            discArtworkURL: room.loadedDisc?.artworkURL
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
        action == .previous
            ? (swipeSourceTrack == nil ? adjacentTrack(for: .previous) : swipePreviousTrack)
            : (swipeSourceTrack == nil ? adjacentTrack(for: .next) : swipeNextTrack)
    }

    private func completeSwipe(
        _ action: ListeningMiniPlayerSwipeAction,
        destination: ListeningDiscTrack
    ) {
        captureSwipeSnapshotIfNeeded()
        isCompletingSwipe = true

        swipeFeedbackCount += 1
        room.skip(action == .next ? 1 : -1)

        let targetOffset = (action == .next ? -1.0 : 1.0) * ListeningMiniPlayerSwipeIntent.pageTravel
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swipeOffset = targetOffset
            }
            waitForTrackChange(to: destination.id)
            return
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04), completionCriteria: .logicallyComplete) {
            swipeOffset = targetOffset
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
}

private func tabAccessibilityIdentifier(_ tab: BeforeShowTab) -> String {
    switch tab {
    case .current: return "root.tab.current"
    case .listen: return "root.tab.listen"
    case .footprints: return "root.tab.footprints"
    }
}
