import SwiftUI

struct ListeningTrackInformation: View {
    let room: ListeningRoomCoordinator

    private var duration: TimeInterval? {
        switch room.playbackState {
        case let .ready(_, _, _, duration), let .playing(_, _, _, duration),
             let .paused(_, _, _, duration), let .finished(_, _, duration): duration
        default: nil
        }
    }

    private var progress: Double {
        guard let duration, duration.isFinite, duration > 0, room.elapsed.isFinite else { return 0 }
        return min(1, max(0, room.elapsed / duration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .center, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(room.track?.title ?? BSLocalization.text("无唱片"))
                        .font(BSFont.title)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(2)
                        .accessibilityIdentifier("listening.trackTitle")
                    Text(room.track?.artistName ?? room.display.player.statusText)
                        .font(BSListeningTokens.body)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(2)
                    if room.track != nil {
                        Text(String(format: "%02d / %02d", room.trackIndex + 1, room.mechanism.disc?.tracks.count ?? 0))
                            .font(BSListeningTokens.caption.monospacedDigit())
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: BSSpacing.sm) {
                    Text(room.deviceStatus.label)
                        .font(BSListeningTokens.captionMedium)
                        .foregroundStyle(ListeningStageTokens.status)
                        .accessibilityIdentifier("listening.deviceStatus")
                    CDPlayerMeterView(isPlaying: room.isPlaying && room.isPlaybackVisible)
                }
            }
            HStack(spacing: BSSpacing.sm) {
                Text(room.timeText)
                ProgressView(value: progress)
                    .tint(ListeningStageTokens.status)
                    .accessibilityLabel(BSLocalization.text("播放进度"))
                Text(duration.map(Self.timeText) ?? "--:--")
            }
            .font(BSListeningTokens.caption.monospacedDigit())
            .foregroundStyle(BSColor.Stage.muted)
            .accessibilityIdentifier("listening.progress")
        }
    }

    private static func timeText(_ duration: TimeInterval) -> String {
        guard duration.isFinite else { return "--:--" }
        let seconds = Int(max(0, min(duration, 86400)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
