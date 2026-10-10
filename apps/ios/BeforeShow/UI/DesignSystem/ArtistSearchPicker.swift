import SwiftUI

struct ArtistSearchPicker: View {
    let options: [RecognizedArtist]
    let isLoading: Bool
    let failure: ArtistSearchFailureMessage?
    let onRecovery: () -> Void
    let onPick: (RecognizedArtist) -> Void

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

            if let failure {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text(failure.title))
                        Text(BSLocalization.text(failure.detail))
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
