import SwiftUI

struct ListeningAtmosphere: View {
    let disc: ListeningDisc?
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkColor: Color?

    private var color: Color {
        guard let disc else { return BSColor.Stage.accent }
        if case .compilation = disc.origin { return ListeningSleeveIdentity(disc: disc).color }
        return artworkColor ?? ListeningSleeveIdentity(disc: disc).color
    }

    var body: some View {
        Ellipse()
            .fill(color.opacity(isPlaying ? BSListeningTokens.playingLightOpacity : BSListeningTokens.restingLightOpacity))
            .frame(height: BSListeningTokens.lightHeight)
            .blur(radius: BSListeningTokens.lightBlur)
            .offset(y: BSListeningTokens.lightOffset)
            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: color)
            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: isPlaying)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: disc?.artworkURL) {
                artworkColor = nil
                guard let url = disc?.artworkURL,
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
        VStack(spacing: 6) {
            if room.mechanism.position == .seated, let track = room.track {
                VStack(spacing: 3) {
                    Text(track.title)
                        .font(BSListeningTokens.headline)
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
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
        .frame(minHeight: 58)
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
