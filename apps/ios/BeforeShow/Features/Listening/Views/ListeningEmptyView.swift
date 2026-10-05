import SwiftUI

struct ListeningEmptyView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenShowLibrary: () -> Void

    private var message: String {
        if hasShows {
            ListeningCopy.text("选一场现场，") + "\n" + ListeningCopy.text("听听即将相遇的音乐。")
        } else {
            ListeningCopy.text("添加一场想去的现场，") + "\n" + ListeningCopy.text("唱片就从这里开始。")
        }
    }

    var body: some View {
        BSRootEmptyState(
            iconSystemName: "opticaldisc",
            title: BSLocalization.text(hasShows ? "选定一场现场开始听歌" : "先添加一场现场"),
            message: message,
            actionTitle: BSLocalization.text(hasShows ? "选择现场" : "添加现场"),
            action: hasShows ? onOpenShowLibrary : onAddShow
        )
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
