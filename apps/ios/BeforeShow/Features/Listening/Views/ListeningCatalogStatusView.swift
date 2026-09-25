import SwiftUI

struct ListeningCatalogStatusView: View {
    let title: String
    var subtitle: String? = nil
    var icon = "opticaldisc"
    var isLoading = false
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            Group {
                if isLoading {
                    ProgressView().tint(BSColor.Stage.accent)
                } else {
                    Image(systemName: icon)
                        .font(BSListeningTokens.headline)
                        .foregroundStyle(BSColor.Stage.accent)
                }
            }
            .frame(width: BSListeningTokens.rowAccessory)
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(title)
                    .font(BSListeningTokens.captionMedium)
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(BSListeningTokens.captionMedium)
                    .foregroundStyle(BSColor.Stage.accent)
                    .padding(.horizontal, BSSpacing.compact)
                    .frame(minHeight: BSLayout.minTouchTarget)
                    .background(BSColor.Stage.accent.opacity(BSListeningTokens.selectionFillOpacity), in: Capsule())
                    .buttonStyle(BSListeningPressStyle())
                    .fixedSize()
            }
        }
        .padding(BSSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.md)
                .strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.catalogStatus")
    }
}
