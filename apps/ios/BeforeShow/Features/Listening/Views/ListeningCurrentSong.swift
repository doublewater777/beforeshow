import SwiftUI

struct ListeningCurrentSong: View {
    let room: ListeningRoomCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var player: ListeningPlayerPresentation { room.display.player }
    private var showsInlineGuidance: Bool {
        room.mechanism.position != .seated || room.track == nil
    }
    private var recovery: ListeningRecoveryAction? {
        guard player.recoveryAction == .retryPlayback else { return nil }
        return .retryPlayback
    }

    var body: some View {
        VStack(spacing: BSListeningTokens.songSpacing) {
            if let track = room.track, room.mechanism.position == .seated {
                HStack(spacing: BSSpacing.sm) {
                    Circle()
                        .fill(room.isPlaying ? BSColor.Stage.accent : BSListeningTokens.restingLight)
                        .frame(width: BSListeningTokens.statusDot, height: BSListeningTokens.statusDot)
                    Text(player.statusText)
                        .font(BSListeningTokens.badge)
                        .tracking(BSListeningTokens.statusTracking)
                        .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
                }
                Text(track.title)
                    .font(BSListeningTokens.songTitle)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(track.artistName)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            } else if showsInlineGuidance {
                statusLine
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity(room.display.roomMode == .connecting ? 0 : 1)
                    .accessibilityHidden(room.display.roomMode == .connecting)
                    .accessibilityIdentifier("listening.playerGuidance")
            }

            if let recovery {
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
        .frame(maxWidth: .infinity, minHeight: BSListeningTokens.songHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.track?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.mechanism.position)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: player.phase)
        .onAppear {
            ListeningPlaybackChromeStore.shared.room = room
        }
    }

    private var statusLine: some View {
        Text(room.mechanism.isAutomatic || room.mechanism.position == .removed
             ? ListeningCopy.text("放置唱片中…") : player.statusText)
            .font(BSListeningTokens.caption)
            .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
