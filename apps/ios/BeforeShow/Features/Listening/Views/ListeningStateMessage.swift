import SwiftUI

struct ListeningStateMessage: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isLoading = false
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            ZStack {
                Circle().fill(BSColor.Stage.surfaceRaised)
                Circle().strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
                if isLoading {
                    ProgressView().tint(BSColor.Stage.accent)
                } else {
                    Image(systemName: icon)
                        .font(BSListeningTokens.stateIconFont)
                        .foregroundStyle(BSColor.Stage.accent)
                }
            }
            .frame(width: BSListeningTokens.stateIconSize, height: BSListeningTokens.stateIconSize)
            VStack(spacing: BSSpacing.sm) {
                Text(title)
                    .font(BSListeningTokens.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(BSListeningActionStyle(prominent: false))
                    .frame(maxWidth: BSLayout.emptyStateActionWidth)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSListeningTokens.stateVerticalPadding)
    }
}
