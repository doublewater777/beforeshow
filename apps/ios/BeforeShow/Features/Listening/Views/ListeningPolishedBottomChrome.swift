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

/// iOS 26 Native Tab View Bottom Accessory for BeforeShow playback.
/// Responds to `@Environment(\.tabViewBottomAccessoryPlacement)`:
/// - `.expanded`: Floating Liquid Glass card above the floating Tab Bar.
/// - `.inline`: Seamlessly merges into the minimized Tab Bar on scroll down.
@available(iOS 26.1, *)
struct ListeningBottomAccessory: View {
    let isListenSelected: Bool
    let onSelectListen: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ListeningPlaybackChromeStore.shared
    @State private var artworkImage: UIImage?
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 128.0

    private var room: ListeningRoomCoordinator? { store.room }
    private var track: ListeningDiscTrack? { room?.track }
    private var playerPhase: ListeningPlayerPhase {
        room?.display.player.phase ?? .noDisc
    }
    private var showsPlayingState: Bool {
        ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: playerPhase)
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
        if let room, let track {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: reduceMotion || !showsPlayingState
                )
            ) { timeline in
                Group {
                    switch placement {
                    case .inline:
                        ListeningInlineAccessoryView(
                            room: room,
                            track: track,
                            artwork: displayedArtwork,
                            discAngle: discAngle(at: timeline.date),
                            showsPlayingState: showsPlayingState,
                            onSelectListen: onSelectListen
                        )
                    default:
                        ListeningExpandedAccessoryView(
                            room: room,
                            track: track,
                            artwork: displayedArtwork,
                            discAngle: discAngle(at: timeline.date),
                            showsPlayingState: showsPlayingState,
                            isListenSelected: isListenSelected,
                            onSelectListen: onSelectListen
                        )
                    }
                }
            }
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

/// Expanded floating Liquid Glass accessory card that hovers above the floating Tab Bar.
private struct ListeningExpandedAccessoryView: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let artwork: UIImage?
    let discAngle: Double
    let showsPlayingState: Bool
    let isListenSelected: Bool
    let onSelectListen: () -> Void

    private var progress: Double? {
        guard let duration = track.duration, duration.isFinite, duration > 0 else { return nil }
        return min(max(room.elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            if isListenSelected {
                trackSummary
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(expandedAccessibilityLabel)
            } else {
                Button {
                    onSelectListen()
                } label: {
                    trackSummary
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(expandedAccessibilityLabel)
                .accessibilityHint(BSLocalization.text("返回听"))
            }

            HStack(spacing: 0) {
                Button {
                    room.perform(.playPause)
                } label: {
                    Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(BSColor.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.88))
                .tint(BSColor.textPrimary)
                .disabled(room.busy)
                .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
                .accessibilityIdentifier("listening.miniPlayer.playPause")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .frame(height: 54)
        .background {
            ListeningPolishedLiquidGlassSurface(
                cornerRadius: 18,
                accentGlow: showsPlayingState,
                progress: progress
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.expanded")
    }

    private var trackSummary: some View {
        HStack(spacing: 10) {
            ListeningArtworkDisc(
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

                Text(track.artistName)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expandedAccessibilityLabel: String {
        let state = BSLocalization.text(showsPlayingState ? "正在播放" : "已暂停")
        return "\(BeforeShowTab.listen.localizedTitle)，\(state) \(track.title)，\(track.artistName)"
    }
}

/// Compact inline accessory merged into the minimized Tab Bar during scroll.
private struct ListeningInlineAccessoryView: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let artwork: UIImage?
    let discAngle: Double
    let showsPlayingState: Bool
    let onSelectListen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSelectListen()
            } label: {
                HStack(spacing: 8) {
                    ListeningArtworkDisc(
                        artwork: artwork,
                        angle: discAngle,
                        size: 26,
                        isPlaying: showsPlayingState
                    )

                    Text(track.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel("\(track.title)，\(track.artistName)")
            .accessibilityHint(BSLocalization.text("返回听"))

            Button {
                room.perform(.playPause)
            } label: {
                Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BSColor.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.88))
            .tint(BSColor.textPrimary)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.inlinePlayPause")
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.inline")
    }
}

/// Rotating optical disc view with CD grooves, rainbow refraction, and center spindle.
private struct ListeningArtworkDisc: View {
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

            // Realistic CD optical groove rings
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
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
                .stroke(Color.white.opacity(0.60), lineWidth: 0.6)
                .frame(width: size * 0.12, height: size * 0.12)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .transaction { $0.animation = nil }
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
                    lineWidth: 0.8
                )
        )
        .rotationEffect(.degrees(angle))
        .shadow(color: isPlaying ? BSColor.Accent.info.opacity(0.18) : Color.clear, radius: 6)
        .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
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

/// Liquid Glass surface styling for floating accessory.
private struct ListeningPolishedLiquidGlassSurface: View {
    let cornerRadius: CGFloat
    var accentGlow: Bool = false
    var progress: Double? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Apple Ultra Thin Material blur base
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // 2. Crystal luminous frosted glass wash (pure, airy, translucent)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.18), location: 0.0),
                            .init(color: Color.white.opacity(0.06), location: 0.45),
                            .init(color: Color.white.opacity(0.02), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 3. Subtle accent glow when playing
            if accentGlow {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BSColor.Accent.info.opacity(0.10),
                                BSColor.Accent.info.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            // 4. Precision hairline progress bar docked flush along the bottom curve
            if let progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1.5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        BSColor.Accent.info.opacity(0.95),
                                        BSColor.Accent.info.opacity(0.70)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(2, proxy.size.width * progress), height: 1.5)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

            // 5. Precision Fresnel specular rim light (Apple glass beveled reflection)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.55), location: 0.0),
                            .init(color: Color.white.opacity(0.20), location: 0.35),
                            .init(color: Color.white.opacity(0.06), location: 0.70),
                            .init(color: accentGlow ? BSColor.Accent.info.opacity(0.35) : Color.white.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
        // Multi-layer airy shadows
        .shadow(
            color: accentGlow ? BSColor.Accent.info.opacity(0.18) : Color.clear,
            radius: 10,
            y: 2
        )
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 5)
        .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
    }
}

/// iOS 18–25 fallback: a stable mini player above the native Tab Bar.
/// No inline morphing is attempted on older systems; the system TabView owns
/// navigation and this accessory only exposes now-playing + play/pause.
struct ListeningLegacyBottomAccessory: View {
    let onSelectListen: () -> Void

    @State private var store = ListeningPlaybackChromeStore.shared
    @State private var artworkImage: UIImage?

    private var room: ListeningRoomCoordinator? { store.room }
    private var track: ListeningDiscTrack? { room?.track }
    private var showsPlayingState: Bool {
        guard let room else { return false }
        return ListeningMiniPlayerPlaybackAppearance.showsPlayingState(for: room.display.player.phase)
    }
    private var artworkURL: URL? {
        guard let room, let track else { return nil }
        return ListeningMiniPlayerArtworkSource.resolve(
            trackArtworkURL: track.artworkURL,
            discArtworkURL: room.mechanism.disc?.artworkURL
        )
    }

    var body: some View {
        if let room, let track {
            HStack(spacing: 8) {
                Button(action: onSelectListen) {
                    HStack(spacing: 10) {
                        ListeningArtworkDisc(
                            artwork: artworkImage,
                            angle: 0,
                            size: 38,
                            isPlaying: showsPlayingState
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BSColor.textPrimary)
                                .lineLimit(1)

                            Text(track.artistName)
                                .font(.caption)
                                .foregroundStyle(BSColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                .accessibilityLabel("\(track.title)，\(track.artistName)")
                .accessibilityHint(BSLocalization.text("返回听"))

                Button {
                    room.perform(.playPause)
                } label: {
                    Image(systemName: showsPlayingState ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(BSColor.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.88))
                .disabled(room.busy)
                .accessibilityLabel(BSLocalization.text(showsPlayingState ? "暂停" : "播放"))
                .accessibilityIdentifier("listening.miniPlayer.legacyPlayPause")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(height: 56)
            .background {
                ListeningPolishedLiquidGlassSurface(
                    cornerRadius: 20,
                    accentGlow: showsPlayingState,
                    progress: nil
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("listening.miniPlayer.legacy")
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
        }
    }
}

/// Compatibility wrapper for standalone bottom chrome preview.
struct ListeningPolishedBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.1, *) {
            ListeningBottomAccessory(
                isListenSelected: selectedTab == .listen,
                onSelectListen: { selectedTab = .listen }
            )
        } else {
            ListeningLegacyBottomAccessory(
                onSelectListen: { selectedTab = .listen }
            )
        }
    }
}
