import SwiftUI

struct ListeningArtistChip<Artwork: View>: View {
    let title: String
    let isSelected: Bool
    var isConnected = true
    @ViewBuilder let artwork: Artwork

    var body: some View {
        HStack(spacing: BSSpacing.xs) {
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
        .foregroundStyle(isSelected ? BSColor.Stage.foreground : BSColor.Stage.muted)
        .padding(.horizontal, BSSpacing.sm)
        .frame(minHeight: BSLayout.minTouchTarget)
        .background(isSelected ? BSColor.Stage.surfaceRaised : .clear, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isSelected ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionRestingOpacity) : .clear,
                lineWidth: BSListeningTokens.hairline
            )
        }
        .contentShape(Capsule())
    }
}
