import SwiftUI

struct ListeningDiscTrackRow: View {
    let index: Int
    let track: ListeningDiscTrack
    let state: ListeningDiscTrackRowState
    let isMultiArtist: Bool
    let showsPlaybackToggle: Bool

    var body: some View {
        HStack(alignment: .center, spacing: BSSpacing.compact) {
            leadingIndicator
                .frame(width: BSListeningTokens.rowAccessory, alignment: .leading)

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(track.title)
                    .font(BSListeningTokens.body)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                if isMultiArtist {
                    Text(track.artistName)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BSSpacing.sm)

            if let duration = track.duration, duration.isFinite, duration > 0 {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                    .font(BSListeningTokens.rowNumber)
                    .foregroundStyle(BSColor.Stage.muted)
            }

            if showsPlaybackToggle {
                playbackControl
            }
        }
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget, alignment: .leading)
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, BSSpacing.sm)
        .background(state.isActive ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionFillOpacity) : Color.clear,
                    in: RoundedRectangle(cornerRadius: BSRadius.sm))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch state {
        case .preparing:
            ProgressView()
                .controlSize(.small)
                .tint(BSColor.Stage.accent)
        case .playing:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BSColor.Stage.accent)
        case .paused:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BSColor.Stage.accent.opacity(0.65))
        case .normal:
            trackNumber(color: BSColor.Stage.dim)
        case .unavailable:
            trackNumber(color: BSColor.Stage.muted)
        }
    }

    @ViewBuilder
    private var playbackControl: some View {
        switch state {
        case .playing:
            playbackControlIcon("pause.fill")
        case .paused:
            playbackControlIcon("play.fill")
        case .normal, .preparing, .unavailable:
            EmptyView()
        }
    }

    private func playbackControlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 28, height: 28)
            .background(BSColor.Stage.accent, in: Circle())
            .accessibilityHidden(true)
    }

    private var titleColor: Color {
        switch state {
        case .preparing, .playing, .paused:
            BSColor.Stage.accent
        case .normal:
            BSColor.Stage.foreground
        case .unavailable:
            BSColor.Stage.muted
        }
    }

    private func trackNumber(color: Color) -> some View {
        Text(String(format: "%02d", index + 1))
            .font(BSListeningTokens.rowNumber)
            .foregroundStyle(color)
    }
}
