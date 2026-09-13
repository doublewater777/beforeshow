import SwiftUI

/// Bottom-of-screen stage glows matching the "当前" and "足迹" tabs.
struct ListeningStageBackground: View {
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    listeningGlow(color: Color(red: 0.69, green: 0.36, blue: 1.0).opacity(0.18))
                        .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.58)
                        .position(x: geometry.size.width * 0.50, y: geometry.size.height * 1.02)

                    listeningGlow(color: Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.12))
                        .frame(width: geometry.size.width * 0.58, height: geometry.size.height * 0.40)
                        .position(x: geometry.size.width * 0.18, y: geometry.size.height * 0.92)

                    listeningGlow(color: Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.10))
                        .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.34)
                        .position(x: geometry.size.width * 0.82, y: geometry.size.height * 0.92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private func listeningGlow(color: Color) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .blur(radius: 22)
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
