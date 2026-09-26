import SwiftUI

struct ListeningArtistChip<Artwork: View>: View {
    let title: String
    let isSelected: Bool
    var isConnected = true
    @ViewBuilder let artwork: Artwork

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            artwork
                .frame(width: BSListeningTokens.avatar, height: BSListeningTokens.avatar)
                .accessibilityHidden(true)
            Text(title)
                .font(BSListeningTokens.captionMedium)
                .lineLimit(1)
            if !isConnected {
                Image(systemName: "link.badge.plus")
                    .font(BSListeningTokens.caption)
            }
        }
        .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.muted)
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: BSLayout.minTouchTarget)
        .background(isSelected ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionFillOpacity) : BSColor.Stage.surface.opacity(BSListeningTokens.inactiveFillOpacity), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isSelected ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionBorderOpacity) : BSColor.Stage.border,
                lineWidth: BSListeningTokens.hairline
            )
        }
        .contentShape(Capsule())
    }
}
