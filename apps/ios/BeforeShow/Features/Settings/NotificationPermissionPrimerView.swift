import SwiftUI

/// 系统权限弹窗之前的一句说明。
///
/// 直接弹系统弹窗时，用户并不知道会收到什么，只能凭「通知」两个字决定。
/// 这里先说清节奏和边界（不推销），再把系统弹窗交出去。
struct NotificationPermissionPrimerView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .medium, fitsContent: true) {
            VStack(spacing: BSSpacing.lg) {
                BSStageSheetHeader(
                    icon: "bell.badge",
                    title: BSLocalization.text("开场之前，我来提醒你"),
                    subtitle: BSLocalization.text("在几个值得记一下的节点轻轻提醒，不推销任何东西。")
                )

                VStack(alignment: .leading, spacing: BSSpacing.compact) {
                    primerRow(
                        icon: "calendar",
                        text: BSLocalization.text("开场前两周、一周、三天，慢慢进入状态")
                    )
                    primerRow(
                        icon: "sun.max",
                        text: BSLocalization.text("现场当天早上提醒出门，开场前再提醒一次")
                    )
                    primerRow(
                        icon: "moon.stars",
                        text: BSLocalization.text("只有快开场那条会响，其余只弹横幅不发声")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: BSSpacing.sm) {
                    Button(BSLocalization.text("好，提醒我")) {
                        onContinue()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())

                    Button(BSLocalization.text("暂时不用")) {
                        onSkip()
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        }
    }

    private func primerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BSSpacing.compact) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
