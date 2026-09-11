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
            + 5
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
                    Label(BSLocalization.text("查看全部"), systemImage: "chevron.right")
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

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight, alignment: .bottom)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), BSColor.Stage.accent.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.22, blue: 0.24),
                            Color(red: 0.11, green: 0.11, blue: 0.12),
                            Color(red: 0.05, green: 0.05, blue: 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
                    .shadow(color: Color.black.opacity(0.6), radius: 4, y: 2)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(height: fixedHeight, alignment: .top)
    }
}
