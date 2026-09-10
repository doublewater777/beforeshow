import SwiftUI

struct ListeningCatalogStatusView: View {
    let title: String
    var subtitle: String? = nil
    var isLoading = false
    var actionTitle: String? = nil
    var action: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(BSColor.Stage.accent)
                        .frame(width: BSListeningTokens.statusIcon)
                }
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
                if !dynamicTypeSize.isAccessibilitySize { actionButton }
            }
            if dynamicTypeSize.isAccessibilitySize { actionButton }
        }
        .padding(BSSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.catalogStatus")
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle {
            Button(actionTitle, action: action)
                .font(BSListeningTokens.captionMedium)
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, BSSpacing.md)
                .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
                .buttonStyle(BSListeningPressStyle())
        }
    }
}
