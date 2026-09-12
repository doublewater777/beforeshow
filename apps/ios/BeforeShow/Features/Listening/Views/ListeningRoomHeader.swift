import SwiftUI

struct ListeningPageHeader<Trailing: View>: View {
    private let trailing: Trailing

    init(@ViewBuilder trailing: () -> Trailing) {
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundStyle(BSColor.Stage.foreground)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            trailing
        }
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }
}

struct ListeningHeaderActionButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ListeningRoomHeader: View {
    let mode: ListeningRoomPlaybackMode

    var body: some View {
        ListeningPageHeader {
            playbackModeStatus
        }
        .zIndex(1)
    }

    private var playbackModeStatus: some View {
        HStack(spacing: 5) {
            Group {
                if mode == .connecting {
                    ProgressView()
                        .tint(BSColor.Stage.accent)
                        .controlSize(.mini)
                } else {
                    Image(systemName: modeIcon(mode))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: BSListeningTokens.statusIcon, height: BSListeningTokens.statusIcon)

            Text(mode.title)
                .font(.system(size: 12, weight: mode == .fullPlayback ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(mode == .fullPlayback ? BSColor.Stage.accent : BSColor.Stage.muted)
        .accessibilityElement(children: .combine)
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
