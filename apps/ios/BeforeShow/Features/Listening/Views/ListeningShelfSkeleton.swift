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
            ListeningSleeveCard(
                disc: .init(id: "skeleton", title: "Album", artworkURL: nil, tracks: []),
                isLoaded: false
            )
            Text("Album title")
                .font(BSListeningTokens.captionMedium)
                .frame(width: 94)
                .frame(height: BSListeningTokens.shelfLabelHeight)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
