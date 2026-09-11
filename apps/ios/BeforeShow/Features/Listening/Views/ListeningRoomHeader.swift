import SwiftUI

struct ListeningRoomHeader: View {
    let mode: ListeningRoomPlaybackMode

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            playbackModeBadge
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(BSColor.Stage.foreground)
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
        .padding(.bottom, BSSpacing.sm)
        .zIndex(1)
    }

    private var playbackModeBadge: some View {
        HStack(spacing: 5) {
            Group {
                if mode == .connecting {
                    ProgressView()
                        .tint(BSColor.Stage.accent)
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: modeIcon(mode))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(width: BSListeningTokens.statusIcon, height: BSListeningTokens.statusIcon)
            if mode != .connecting {
                Text(mode.title)
                    .font(.system(size: 12, weight: mode == .fullPlayback ? .semibold : .medium))
            }
        }
        .foregroundStyle(mode == .fullPlayback ? BSColor.Stage.accent : BSColor.Stage.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            mode == .fullPlayback ? BSColor.Stage.accent.opacity(0.12) : Color.white.opacity(0.06),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                mode == .fullPlayback ? BSColor.Stage.accent.opacity(0.3) : BSColor.Stage.border,
                lineWidth: 0.75
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityIdentifier("listening.playbackMode")
    }

    private func modeIcon(_ mode: ListeningRoomPlaybackMode) -> String {
        switch mode {
        case .connecting: "hourglass"
        case .fullPlayback: "apple.logo"
        case .preview: "waveform"
        case .metadataOnly: "list.bullet.rectangle"
        case .unavailable: "exclamationmark.triangle"
        }
    }

}
