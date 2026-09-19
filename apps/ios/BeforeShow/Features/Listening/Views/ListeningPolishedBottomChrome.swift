import SwiftUI
import UIKit

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

enum ListeningPolishedBottomChromeMode: Equatable {
    case tabsOnly
    case fullPlayer
    case compactPlayer

    static func resolve(selectedTab: BeforeShowTab, hasLoadedDisc: Bool) -> Self {
        guard hasLoadedDisc else { return .tabsOnly }
        return selectedTab == .listen ? .fullPlayer : .compactPlayer
    }
}

/// Fixed three-slot root chrome.
/// Current and Footprints never disappear; only the center Listen slot morphs into playback.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ListeningPlaybackChromeStore.shared
    @State private var artworkImage: UIImage?
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 128.0

    private var room: ListeningRoomCoordinator? { store.room }
    private var track: ListeningDiscTrack? { room?.track }
    private var hasLoadedDisc: Bool {
        guard let room, room.mechanism.hasDisc, room.track != nil else { return false }
        return true
    }
    private var playerPhase: ListeningPlayerPhase {
        room?.display.player.phase ?? .noDisc
    }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: playerPhase)
    }
    private var mode: ListeningPolishedBottomChromeMode {
        .resolve(selectedTab: selectedTab, hasLoadedDisc: hasLoadedDisc)
    }
    private var artworkURL: URL? {
        guard let room, let track else { return nil }
        return ListeningMiniPlayerArtworkSource.resolve(
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
            VStack(spacing: 7) {
                if mode == .fullPlayer, let room, let track {
                    ListeningExpandedChromePlayer(
                        room: room,
                        track: track,
                        artwork: displayedArtwork,
                        discAngle: discAngle(at: timeline.date),
                        currentDate: timeline.date,
                        showsPlayingState: showsPlayingState
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ListeningFixedRootTabBar(
                    selectedTab: $selectedTab,
                    room: room,
                    track: track,
                    artwork: displayedArtwork,
                    discAngle: discAngle(at: timeline.date),
                    showsPlayingState: showsPlayingState,
                    mode: mode
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.90),
            value: mode
        )
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

private struct ListeningExpandedChromePlayer: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let artwork: UIImage?
    let discAngle: Double
    let currentDate: Date
    let showsPlayingState: Bool

    private var lidIsOpen: Bool {
        (room.mechanism.motion.lid.target ?? room.mechanism.motion.lid.value) > 0.5
    }
    private var progress: Double? {
        guard let duration = track.duration, duration.isFinite, duration > 0 else { return nil }
        return min(max(room.elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                ListeningPolishedArtworkDisc(
                    artwork: artwork,
                    angle: discAngle,
                    size: 40,
                    isPlaying: showsPlayingState
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(track.artistName)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)

                        if showsPlayingState {
                            ListeningPolishedMiniEqualizer(
                                currentDate: currentDate,
                                maxHeight: 8
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            Button {
                room.perform(.open)
            } label: {
                ListeningPolishedLidGlyph(isOpen: lidIsOpen)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.90))
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text("打开或关闭上盖"))
            .accessibilityIdentifier("listening.miniPlayer.open")

            Button {
                room.perform(.playPause)
            } label: {
                Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BSColor.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Accent.info.opacity(0.22), lineWidth: 0.8))
                    .contentShape(Circle())
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.88))
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.playPause")
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 54)
        .background {
            ListeningPolishedPlayerSurface(
                cornerRadius: 18,
                accentGlow: showsPlayingState,
                progress: progress
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.expanded")
    }
}

private struct ListeningFixedRootTabBar: View {
    @Binding var selectedTab: BeforeShowTab
    let room: ListeningRoomCoordinator?
    let track: ListeningDiscTrack?
    let artwork: UIImage?
    let discAngle: Double
    let showsPlayingState: Bool
    let mode: ListeningPolishedBottomChromeMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            rootTab(.current)

            if mode == .compactPlayer, let room, let track {
                compactListenPlayer(room: room, track: track)
                    .frame(minWidth: 164, maxWidth: .infinity)
                    .layoutPriority(2)
            } else {
                rootTab(.listen)
            }

            rootTab(.footprints)
        }
        .padding(6)
        .frame(height: 66)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(Color.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 22, y: 10)
        .accessibilityIdentifier("root.customTabBar")
    }

    private func rootTab(_ tab: BeforeShowTab) -> some View {
        let selected = selectedTab == tab
        let compact = mode == .compactPlayer
        let showLabel = !compact || selected

        return Button {
            select(tab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: .medium))

                if showLabel {
                    Text(tab.localizedTitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? BSColor.Stage.accent : Color.white.opacity(0.66))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(BSColor.Stage.accent.opacity(0.16), lineWidth: 1)
                        }
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
        HStack(spacing: 6) {
            Button {
                select(.listen)
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ListeningPolishedArtworkDisc(
                            artwork: artwork,
                            angle: discAngle,
                            size: 30,
                            isPlaying: showsPlayingState
                        )
                        Text(track.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                    }

                    ListeningPolishedArtworkDisc(
                        artwork: artwork,
                        angle: discAngle,
                        size: 30,
                        isPlaying: showsPlayingState
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.title)，\(track.artistName)")
            .accessibilityHint(BSLocalization.text("返回听"))

            Button {
                room.perform(.playPause)
            } label: {
                Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BSColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.045), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.88))
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.inlinePlayPause")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background {
            ListeningPolishedPlayerSurface(
                cornerRadius: 22,
                accentGlow: showsPlayingState
            )
        }
        .accessibilityIdentifier("listening.miniPlayer.compact")
    }

    private func select(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.90)) {
                selectedTab = tab
            }
        }
    }
}

private struct ListeningPolishedLidGlyph: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 1.4)
                .frame(width: 18, height: 10)
                .offset(y: 4)

            Circle()
                .stroke(BSColor.Accent.info.opacity(0.68), lineWidth: 1.1)
                .frame(width: 6, height: 6)
                .offset(y: 4)

            Capsule()
                .fill(Color.white.opacity(0.76))
                .frame(width: 18, height: 1.5)
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: .leading)
                .offset(x: isOpen ? 1 : 0, y: isOpen ? -4 : -2)
        }
        .background(Color.white.opacity(0.045), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isOpen)
    }
}

private struct ListeningPolishedArtworkDisc: View {
    let artwork: UIImage?
    let angle: Double
    let size: CGFloat
    var isPlaying: Bool = false

    var body: some View {
        ZStack {
            if isPlaying {
                Circle()
                    .fill(BSColor.Accent.info.opacity(0.25))
                    .frame(width: size + 4, height: size + 4)
                    .blur(radius: 5)
            }

            Circle().fill(BSColor.Stage.surface)

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .transaction { $0.animation = nil }
            } else {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    Image(systemName: "opticaldisc")
                        .font(.system(size: size * 0.48, weight: .regular))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                .frame(width: size * 0.72, height: size * 0.72)

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
        .rotationEffect(.degrees(angle))
        .shadow(color: isPlaying ? BSColor.Accent.info.opacity(0.18) : Color.clear, radius: 6)
        .accessibilityHidden(true)
    }
}

private struct ListeningPolishedPlayerSurface: View {
    let cornerRadius: CGFloat
    var accentGlow = false
    var progress: Double? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.13),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if accentGlow {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BSColor.Accent.info.opacity(0.10),
                                Color.clear,
                                Color.purple.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            if let progress {
                GeometryReader { proxy in
                    Capsule()
                        .fill(BSColor.Accent.info.opacity(0.82))
                        .frame(width: max(2, proxy.size.width * progress), height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.white.opacity(0.08),
                            BSColor.Accent.info.opacity(accentGlow ? 0.30 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(0.24), radius: 14, y: 5)
    }
}

private struct ListeningPolishedMiniEqualizer: View {
    let currentDate: Date
    let maxHeight: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(BSColor.Accent.info)
                    .frame(width: 1.8, height: height(for: index))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func height(for index: Int) -> CGFloat {
        let t = currentDate.timeIntervalSinceReferenceDate
        let frequencies: [Double] = [8.5, 12.8, 6.9]
        let phases: [Double] = [0.0, 1.8, 3.4]
        let wave = (sin(t * frequencies[index] + phases[index]) + 1) / 2
        return 2 + CGFloat(wave) * (maxHeight - 2)
    }
}
