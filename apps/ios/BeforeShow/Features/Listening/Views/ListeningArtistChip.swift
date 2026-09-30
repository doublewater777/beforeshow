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
                .opacity(isConnected ? 1.0 : 0.6)
                .accessibilityHidden(true)
            Text(title)
                .font(BSListeningTokens.captionMedium)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
                .truncationMode(.tail)
        }
        .foregroundStyle(isSelected ? BSColor.Stage.accent : (isConnected ? BSColor.Stage.muted : BSColor.Stage.muted.opacity(0.68)))
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: BSLayout.minTouchTarget)
        .background(
            isSelected
                ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionFillOpacity)
                : BSColor.Stage.surface.opacity(BSListeningTokens.inactiveFillOpacity),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                isSelected
                    ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionBorderOpacity)
                    : (isConnected ? BSColor.Stage.border : BSColor.Stage.border.opacity(0.5)),
                lineWidth: BSListeningTokens.hairline
            )
        }
        .animation(BSListeningTokens.selectionAnimation, value: isSelected)
        .contentShape(Capsule())
    }
}
