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
                .background(Color.white.opacity(0.045))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )

            Text(hasShows ? BSLocalization.text("选定一场现场开始听歌") : BSLocalization.text("先添加一场现场"))
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(hasShows
                 ? BSLocalization.text("选定演出开启专属唱片机，\n提前熟悉现场歌单与作品。")
                 : BSLocalization.text("把要去的音乐现场放进来，\n开启唱片机，提前预习演出曲目。"))
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)

            Button(action: hasShows ? onOpenShowLibrary : onAddShow) {
                Text(hasShows ? BSLocalization.text("选择现场") : BSLocalization.text("添加现场"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
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
