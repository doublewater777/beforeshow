import SwiftUI

/// Shared empty state for the three root tabs (当前 / 听 / 足迹).
/// Title and message always reserve two lines so block height stays stable
/// across tabs with different copy lengths. Bottom chrome clearance is applied
/// manually so NavigationStack vs non-stack hosts stay vertically aligned.
struct BSRootEmptyState<Preview: View>: View {
    let iconSystemName: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer(minLength: 0)

            Image(systemName: iconSystemName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(BSColor.Stage.accent)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))

            Text(title)
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)

            Text(message)
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)

            preview

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, BSSpacing.sm)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSSpacing.xl)
        .padding(.bottom, BSLayout.floatingTabBarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }
}

extension BSRootEmptyState where Preview == EmptyView {
    init(iconSystemName: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.init(iconSystemName: iconSystemName, title: title, message: message, actionTitle: actionTitle, action: action) { EmptyView() }
    }
}
