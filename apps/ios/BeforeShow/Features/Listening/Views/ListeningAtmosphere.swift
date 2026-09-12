import SwiftUI

/// One light field and tabletop for both the sleeves and the player.
struct ListeningAtmosphere: View {
    let disc: ListeningDisc?
    let isPlaying: Bool
    var isOpen = false
    var hasDisc = false
    var show: Show?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var artworkColor: Color?
    @State private var isVisible = false

    private var color: Color {
        guard let disc else { return BSColor.Stage.accent }
        return artworkColor ?? ListeningSleeveIdentity(disc: disc).color
    }

    private var artworkURL: URL? {
        guard let disc else { return nil }
        return ListeningSleeveIdentity(disc: disc, show: show).artworkURL
            ?? disc.tracks.compactMap(\.artworkURL).first
    }

    private var lightOpacity: Double {
        if isPlaying { return BSListeningTokens.playingLightOpacity }
        if isOpen { return BSListeningTokens.openLightOpacity }
        return hasDisc ? BSListeningTokens.pausedLightOpacity : BSListeningTokens.restingLightOpacity
    }

    private var breathes: Bool {
        isPlaying && !reduceMotion && isVisible && scenePhase == .active
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let tableTop = height * BSListeningTokens.tableTopFraction
            let table = Path { path in
                path.move(to: CGPoint(x: width * BSListeningTokens.tableRearInset, y: tableTop))
                path.addLine(to: CGPoint(x: width * (1 - BSListeningTokens.tableRearInset), y: tableTop))
                path.addLine(to: CGPoint(x: width * (1 - BSListeningTokens.tableFrontInset), y: height))
                path.addLine(to: CGPoint(x: width * BSListeningTokens.tableFrontInset, y: height))
                path.closeSubpath()
            }
            ZStack {
                table.fill(LinearGradient(
                    colors: [BSListeningTokens.tableTop, BSListeningTokens.tableBottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                RadialGradient(
                    colors: [.white.opacity(BSListeningTokens.sideLightOpacity), .clear],
                    center: BSListeningTokens.sideLightCenter,
                    startRadius: 0, endRadius: width * BSListeningTokens.tableLightRadiusFraction
                )
                .clipShape(table)
                Path { path in
                    path.move(to: CGPoint(x: width * BSListeningTokens.tableRearInset, y: tableTop))
                    path.addLine(to: CGPoint(x: width * (1 - BSListeningTokens.tableRearInset), y: tableTop))
                }
                .stroke(LinearGradient(
                    colors: [.clear, .white.opacity(BSListeningTokens.tableEdgeOpacity), .clear],
                    startPoint: .leading, endPoint: .trailing
                ), lineWidth: BSListeningTokens.hairline)

                TimelineView(.animation(minimumInterval: BSListeningTokens.lightFrameInterval, paused: !breathes)) { timeline in
                    let breath = breathes
                        ? sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / BSListeningTokens.lightBreathPeriod) * BSListeningTokens.lightBreathAmplitude
                        : 0
                    RadialGradient(
                        colors: [color.opacity(lightOpacity + breath), .clear],
                        center: BSListeningTokens.ambientLightCenter,
                        startRadius: 0, endRadius: width * BSListeningTokens.roomLightRadiusFraction
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: lightOpacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: color)
                }
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: BSListeningTokens.tableFadeStart),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: BSListeningTokens.tableRearInset),
                    .init(color: .white, location: 1 - BSListeningTokens.tableRearInset),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: artworkURL) {
            artworkColor = nil
            guard let url = artworkURL,
                  let image = await ShowCoverImageCache.shared.image(from: url),
                  let sampled = await ArtworkColorSampler.color(in: image), !Task.isCancelled else { return }
            artworkColor = Color(uiColor: sampled)
        }
    }
}

struct ListeningCurrentSong: View {
    let room: ListeningRoomCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var player: ListeningPlayerPresentation { room.display.player }

    var body: some View {
        VStack(spacing: BSListeningTokens.songSpacing) {
            if room.mechanism.position == .seated, let track = room.track {
                VStack(spacing: BSSpacing.xs) {
                    Text(track.title)
                        .font(BSListeningTokens.songTitle)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text(track.artistName)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(2)
                    statusLine
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("listening.currentSong")
                .transition(.opacity)
            } else {
                statusLine
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity(room.display.roomMode == .connecting ? 0 : 1)
                    .accessibilityHidden(room.display.roomMode == .connecting)
                    .accessibilityIdentifier("listening.playerGuidance")
            }

            if let recovery = player.recoveryAction {
                Button(recovery.title) {
                    room.performListeningRecovery(recovery)
                }
                .font(BSListeningTokens.captionMedium)
                .foregroundStyle(BSColor.Stage.accent)
                .frame(minHeight: BSLayout.minTouchTarget)
                .buttonStyle(BSListeningPressStyle(scale: 0.96))
                .accessibilityIdentifier("listening.playerRecovery")
            }
        }
        .frame(minHeight: BSListeningTokens.songHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.track?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.mechanism.position)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: player.phase)
    }

    private var statusLine: some View {
        Text(player.statusText)
            .font(BSListeningTokens.caption)
            .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
