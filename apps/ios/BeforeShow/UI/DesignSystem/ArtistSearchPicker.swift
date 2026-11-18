import SwiftUI

struct ArtistSearchPicker: View {
    let options: [RecognizedArtist]
    let isLoading: Bool
    let failure: ArtistSearchFailureMessage?
    let onRecovery: () -> Void
    let onPick: (RecognizedArtist) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRequestingAccess = false
    private let musicAccess = MusicKitListeningCatalogService()

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            HStack(spacing: BSSpacing.xs) {
                Image(systemName: "music.note")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundStyle(BSColor.textTertiary)
                Text(BSLocalization.text("Apple Music 候选"))
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.textTertiary)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BSColor.textTertiary)
                }
            }
            .padding(.horizontal, BSSpacing.xs)

            if let status = failure?.authorizationStatus {
                authorizationAction(for: status)
                    .font(BSFont.caption)
                    .padding(BSSpacing.xs)
            } else if let failure {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text(key: failure.title))
                        Text(BSLocalization.text(key: failure.detail))
                    }
                    .foregroundStyle(BSColor.textTertiary)
                    Spacer()
                    Button(failure.actionTitle, action: onRecovery)
                        .foregroundStyle(BSColor.Stage.accent)
                }
                .font(BSFont.caption)
                .padding(.horizontal, BSSpacing.xs)
                .padding(.vertical, BSSpacing.xs)
            }
            if options.isEmpty && !isLoading && failure == nil {
                Text(BSLocalization.text("暂无匹配，可直接保存手输名字"))
                    .font(BSFont.V3.small)
                    .foregroundStyle(BSColor.textTertiary)
                    .padding(.horizontal, BSSpacing.xs)
                    .padding(.vertical, BSSpacing.xs)
            }
            if !options.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            Divider()
                                .background(BSColor.borderProminent.opacity(0.5))
                                .padding(.leading, BSSpacing.compact)
                        }
                        ArtistSearchRow(
                            option: option,
                            onPick: { onPick(option) }
                        )
                    }
                }
                .background(BSColor.Stage.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.borderProminent, lineWidth: BSListeningTokens.hairline)
                )
            }
        }
        .padding(.top, BSSpacing.xs)
        .task(id: isRequestingAccess) {
            guard isRequestingAccess else { return }
            _ = await musicAccess.requestAuthorization()
            guard !Task.isCancelled else { return }
            isRequestingAccess = false
            onRecovery()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, failure?.authorizationStatus != nil, !isRequestingAccess,
               musicAccess.currentAuthorizationStatus() == .authorized {
                onRecovery()
            }
        }
    }

    @ViewBuilder
    private func authorizationAction(for status: ListeningMusicAuthorizationStatus) -> some View {
        switch status {
        case .notDetermined:
            Button(BSLocalization.text("连接 Apple Music")) { isRequestingAccess = true }
                .disabled(isRequestingAccess)
                .foregroundStyle(BSColor.Stage.accent)
        case .denied:
            HStack {
                Text(BSLocalization.text("请在系统设置中允许访问 Apple Music"))
                    .foregroundStyle(BSColor.textTertiary)
                Spacer()
                Button(BSLocalization.text("打开设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .foregroundStyle(BSColor.Stage.accent)
            }
        case .restricted:
            Text(String(localized: "Apple Music 访问受到系统限制，无法在此更改。", table: "Listening"))
                .foregroundStyle(BSColor.textTertiary)
        case .authorized:
            EmptyView()
        }
    }
}

private struct ArtistSearchRow: View {
    let option: RecognizedArtist
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: BSSpacing.compact) {
                ArtistAvatarThumb(url: option.avatarURL, size: BSListeningTokens.avatar)
                Text(option.canonicalName)
                    .font(BSFont.body.weight(.semibold))
                    .foregroundStyle(BSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.accent)
            }
            .padding(.horizontal, BSSpacing.compact)
            .padding(.vertical, BSSpacing.sm)
            .frame(minHeight: BSLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
