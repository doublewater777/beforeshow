import SwiftUI

struct ListeningEmptyView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenShowLibrary: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "opticaldisc")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))

            Text(hasShows ? BSLocalization.text("选定一场现场开始听歌") : BSLocalization.text("先添加一场现场"))
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(ListeningCopy.text(hasShows ? "选一场现场，听听即将相遇的音乐。" : "添加一场想去的现场，唱片就从这里开始。"))
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: hasShows ? onOpenShowLibrary : onAddShow) {
                Text(BSLocalization.text(hasShows ? "选择现场" : "添加现场"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
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
        }
    }
}
