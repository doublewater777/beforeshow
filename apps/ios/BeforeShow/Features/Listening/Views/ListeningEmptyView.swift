import SwiftUI

struct ListeningEmptyView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenShowLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ListeningPageHeader {
                HStack(spacing: BSSpacing.sm) {
                    if hasShows {
                        ListeningHeaderActionButton(
                            icon: "list.bullet.rectangle",
                            accessibilityLabel: BSLocalization.text("全部现场"),
                            action: onOpenShowLibrary
                        )
                    }
                    ListeningHeaderActionButton(
                        icon: "plus",
                        accessibilityLabel: BSLocalization.text("添加现场"),
                        action: onAddShow
                    )
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: BSSpacing.md) {
                Text(ListeningCopy.text(hasShows ? "选一场现场，" : "添加一场想去的现场，"))
                Text(ListeningCopy.text(hasShows ? "听听即将相遇的音乐。" : "唱片就从这里开始。"))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.6))
            }
            .font(ListeningOverviewStyle.serif(30))
            .multilineTextAlignment(.center)
            .padding(.horizontal, BSSpacing.roomy)
            Rectangle().fill(BSColor.Stage.foreground.opacity(0.3)).frame(width: 32, height: 1)
                .padding(.vertical, BSSpacing.lg)
            Button(action: hasShows ? onOpenShowLibrary : onAddShow) {
                Text(BSLocalization.text(hasShows ? "全部现场" : "添加现场"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.background)
                    .padding(.horizontal, BSSpacing.lg)
                    .frame(height: 44)
                    .background(Capsule().fill(BSColor.Stage.foreground))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.empty.action")
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .bsAdaptiveContentWidth()
        .foregroundStyle(BSColor.Stage.foreground)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}
