import SwiftUI

/// Keeps the cabinet and player in place as catalog content arrives.
struct ListeningShelfView<Content: View>: View {
    let title: String
    let count: String
    var isLoading = false
    var showsAllDiscs = false
    var showAll: () -> Void = {}
    @ViewBuilder let content: Content

    private let contentHeight = BSListeningTokens.shelfContentHeight
    private var fixedHeight: CGFloat {
        BSLayout.minTouchTarget
            + BSSpacing.xs / 2
            + BSSpacing.sm
            + contentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(count)
                    .font(BSListeningTokens.badge)
                    .foregroundStyle(BSColor.Stage.muted)
                    .padding(.horizontal, BSListeningTokens.shelfItemSpacing)
                    .padding(.vertical, BSSpacing.xs / 2)
                    .background(BSColor.Stage.surfaceRaised, in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .accessibilityHidden(isLoading)
                Spacer(minLength: 0)
                Button(action: showAll) {
                    HStack(spacing: 3) {
                        Text(BSLocalization.text("查看全部"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minHeight: BSLayout.minTouchTarget)
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.95))
                .opacity(showsAllDiscs ? 1 : 0)
                .disabled(!showsAllDiscs)
                .accessibilityHidden(!showsAllDiscs)
                .accessibilityIdentifier("listening.allDiscs")
            }
            .frame(height: BSLayout.minTouchTarget)
            .padding(.top, BSSpacing.xs / 2)

            content
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight, alignment: .bottom)
        }
        .frame(height: fixedHeight, alignment: .top)
    }
}
