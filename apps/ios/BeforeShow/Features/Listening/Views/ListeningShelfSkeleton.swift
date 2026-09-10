import SwiftUI

struct ListeningShelfSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: BSSpacing.compact) {
                ForEach(0..<BSListeningTokens.Shelf.loadingSlotCount, id: \.self) { _ in
                    ListeningCabinetDiscPlaceholder()
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
        .accessibilityIdentifier("listening.shelfSkeleton")
    }
}

private struct ListeningCabinetDiscPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BSListeningTokens.shelfItemSpacing) {
            ListeningSleeveCard(
                disc: .init(id: "skeleton", title: "Album", artworkURL: nil, tracks: []),
                isLoaded: false
            )
            Text("Album title")
                .font(BSListeningTokens.captionMedium)
                .frame(width: 94, alignment: .leading)
                .frame(height: BSListeningTokens.shelfLabelHeight, alignment: .leading)
        }
        .frame(width: BSListeningTokens.shelfItemWidth, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
