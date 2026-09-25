import SwiftUI

/// Keeps the cabinet and player in place as catalog content arrives.
struct ListeningShelfView<Content: View>: View {
    let title: String?
    let count: String
    var isLoading = false
    var showsAllDiscs = false
    var showAll: () -> Void = {}
    @ViewBuilder let content: Content

    @ScaledMetric(relativeTo: .caption) private var labelHeight = BSListeningTokens.shelfLabelHeight
    @ScaledMetric(relativeTo: .caption) private var actionHeaderHeight = BSLayout.minTouchTarget
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var headerHeight: CGFloat {
        actionHeaderHeight
    }
    private var contentHeight: CGFloat {
        BSListeningTokens.shelfContentHeight + labelHeight * (dynamicTypeSize.isAccessibilitySize ? 3 : 1) - BSListeningTokens.shelfLabelHeight
    }

    private var fixedHeight: CGFloat {
        headerHeight + BSSpacing.xs + contentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            HStack(spacing: BSSpacing.sm) {
                titleLabel
                Text(count)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .accessibilityHidden(isLoading)
                Spacer(minLength: 0)
                if showsAllDiscs {
                    Button(action: showAll) {
                        HStack(spacing: BSSpacing.xs) {
                            Text(BSLocalization.text("唱片柜"))
                            Image(systemName: "chevron.right")
                        }
                            .font(BSListeningTokens.captionMedium)
                            .foregroundStyle(BSColor.Stage.accent)
                            .frame(minHeight: BSLayout.minTouchTarget)
                    }
                    .buttonStyle(BSListeningPressStyle())
                    .accessibilityIdentifier("listening.allDiscs")
                }
            }
            .frame(height: headerHeight)

            content
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight, alignment: .bottom)
        }
        .frame(height: fixedHeight, alignment: .top)
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let title {
            Text(title)
                .font(BSListeningTokens.captionMedium)
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

}
