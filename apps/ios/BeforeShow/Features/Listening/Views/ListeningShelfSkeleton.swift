import SwiftUI

struct ListeningShelfSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: BSSpacing.compact) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: BSListeningTokens.shelfItemSpacing) {
                        RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                            .fill(BSColor.Stage.surfaceRaised)
                            .overlay {
                                RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                                    .strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
                            }
                            .frame(width: BSListeningTokens.shelfArtwork, height: BSListeningTokens.shelfArtwork)
                        RoundedRectangle(cornerRadius: BSSpacing.xs, style: .continuous)
                            .fill(BSColor.Stage.surfaceRaised)
                            .frame(width: BSListeningTokens.shelfArtwork, height: BSSpacing.sm)
                            .frame(height: BSListeningTokens.shelfLabelHeight, alignment: .leading)
                    }
                    .frame(width: BSListeningTokens.shelfItemWidth, alignment: .leading)
                }
            }
            .padding(.horizontal, BSSpacing.xs / 2)
            .padding(.vertical, BSSpacing.xs)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
        .accessibilityIdentifier("listening.shelfSkeleton")
    }
}
