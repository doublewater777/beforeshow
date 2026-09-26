import SwiftUI

struct ListeningEmptyView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenShowLibrary: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            ListeningEmptyArtwork()

            Text(hasShows ? BSLocalization.text("选定一场现场开始听歌") : BSLocalization.text("先添加一场现场"))
                .font(BSListeningTokens.stateTitle)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(ListeningCopy.text(hasShows ? "选一场现场，听听即将相遇的音乐。" : "添加一场想去的现场，唱片就从这里开始。"))
                .font(BSListeningTokens.body)
                .foregroundStyle(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: hasShows ? onOpenShowLibrary : onAddShow) {
                Label(BSLocalization.text(hasShows ? "选择现场" : "添加现场"),
                      systemImage: hasShows ? "ticket" : "plus")
            }
            .buttonStyle(BSListeningActionStyle())
            .frame(maxWidth: BSLayout.emptyStateActionWidth)
            .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .padding(.bottom, BSLayout.floatingTabBarClearance)
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
