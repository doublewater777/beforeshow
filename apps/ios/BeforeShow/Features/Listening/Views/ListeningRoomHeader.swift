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
        .buttonStyle(BSListeningPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ListeningRoomHeader: View {
    let mode: ListeningRoomPlaybackMode
    let notice: ListeningHeaderNotice?
    let onRecovery: (ListeningRecoveryAction) -> Void
    @State private var showsExplanation = false

    init(
        mode: ListeningRoomPlaybackMode,
        notice: ListeningHeaderNotice? = nil,
        onRecovery: @escaping (ListeningRecoveryAction) -> Void = { _ in }
    ) {
        self.mode = mode
        self.notice = notice
        self.onRecovery = onRecovery
    }

    var body: some View {
        ListeningPageHeader {
            headerStatus
        }
        .zIndex(1)
        .sheet(isPresented: $showsExplanation) {
            if let notice {
                ListeningPlaybackExplanationSheet(
                    notice: notice,
                    onRecovery: onRecovery
                )
            }
        }
    }

    @ViewBuilder
    private var headerStatus: some View {
        switch mode {
        case .fullPlayback:
            EmptyView()
        case .connecting:
            playbackModeStatus
        case .preview, .metadataOnly, .unavailable:
            Button {
                guard notice != nil else { return }
                showsExplanation = true
            } label: {
                playbackModeStatus
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.96))
            .disabled(notice == nil)
        }
    }

    private var playbackModeStatus: some View {
        HStack(spacing: BSSpacing.xs) {
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
                .font(BSListeningTokens.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(BSColor.Stage.muted)
        .padding(.horizontal, BSSpacing.compact)
        .padding(.vertical, BSSpacing.sm)
        .background(BSColor.Stage.surface, in: Capsule())
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

private struct ListeningPlaybackExplanationSheet: View {
    let notice: ListeningHeaderNotice
    let onRecovery: (ListeningRecoveryAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BSDrawerSheet(detent: .height(180), fitsContent: true) {
            Text(notice.message)
                .font(BSListeningTokens.body)
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let action = notice.recoveryAction {
                Button(action.title) {
                    dismiss()
                    onRecovery(action)
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }
}
