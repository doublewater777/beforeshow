import SwiftUI

/// Keeps the cabinet and player in place as catalog content arrives.
struct ListeningShelfView<Content: View>: View {
    let title: String?
    let count: String
    var isLoading = false
    var showsCount = true
    var showsAllDiscs = false
    var showsCurrentDisc = false
    var showAll: () -> Void = {}
    var showCurrentDisc: () -> Void = {}
    @ViewBuilder let content: Content

    @ScaledMetric(relativeTo: .caption) private var labelHeight = BSListeningTokens.shelfLabelHeight
    @ScaledMetric(relativeTo: .caption) private var headerHeight = BSLayout.minTouchTarget
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var contentHeight: CGFloat {
        BSListeningTokens.shelfContentHeight + labelHeight * (dynamicTypeSize.isAccessibilitySize ? 3 : 1) - BSListeningTokens.shelfLabelHeight
    }

    private var fixedHeight: CGFloat {
        headerHeight + BSSpacing.xs + contentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BSSpacing.sm) {
                titleLabel
                if showsCount {
                    countLabel
                }
                Spacer(minLength: 0)
                if showsCurrentDisc {
                    Button(action: showCurrentDisc) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    }
                    .buttonStyle(BSListeningPressStyle())
                    .accessibilityLabel(BSLocalization.text("已在播放机中"))
                    .accessibilityIdentifier("listening.currentDisc")
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
    private var countLabel: some View {
        if showsAllDiscs {
            Button(action: showAll) {
                HStack(spacing: BSSpacing.xs) {
                    Text(count)
                    Image(systemName: "chevron.right")
                }
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.muted)
                .frame(minHeight: BSLayout.minTouchTarget)
            }
            .buttonStyle(BSListeningPressStyle())
            .redacted(reason: isLoading ? .placeholder : [])
            .accessibilityHidden(isLoading)
            .accessibilityIdentifier("listening.allDiscs")
        } else {
            Text(count)
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.muted)
                .redacted(reason: isLoading ? .placeholder : [])
                .accessibilityHidden(isLoading)
                .accessibilityIdentifier("listening.discCount")
        }
    }
}
