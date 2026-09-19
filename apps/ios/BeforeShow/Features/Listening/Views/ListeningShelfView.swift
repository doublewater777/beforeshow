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
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        titleLabel
                        countView
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        titleLabel
                        countView
                        Spacer(minLength: 0)
                    }
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

    @ViewBuilder
    private var countView: some View {
        if showsAllDiscs {
            Button(action: showAll) {
                HStack(spacing: 3) {
                    Text(count)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minHeight: BSLayout.minTouchTarget)
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.95))
            .accessibilityIdentifier("listening.allDiscs")
        } else {
            Text(count)
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .redacted(reason: isLoading ? .placeholder : [])
                .accessibilityHidden(isLoading)
        }
    }
}
