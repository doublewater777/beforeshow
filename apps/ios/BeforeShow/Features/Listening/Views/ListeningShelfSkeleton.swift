import SwiftUI

struct ListeningShelfSkeleton: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: BSSpacing.compact) {
            ForEach(0..<ListeningDisplayProjector.Shelf.visibleCount, id: \.self) { _ in
                ListeningCabinetDiscPlaceholder()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
        .accessibilityIdentifier("listening.shelfSkeleton")
    }
}

private struct ListeningCabinetDiscPlaceholder: View {
    var body: some View {
        VStack(spacing: BSListeningTokens.shelfItemSpacing) {
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .fill(BSColor.Stage.surfaceRaised)
                .frame(width: BSListeningTokens.shelfArtwork, height: BSListeningTokens.shelfArtwork)
            Capsule()
                .fill(BSColor.Stage.surfaceRaised)
                .frame(width: BSListeningTokens.shelfArtwork, height: BSSpacing.sm)
                .frame(height: BSListeningTokens.shelfLabelHeight)
        }
        .accessibilityHidden(true)
    }
}
