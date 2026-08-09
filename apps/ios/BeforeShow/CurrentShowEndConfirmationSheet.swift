import SwiftUI

struct CurrentShowEndConfirmationSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(
            detents: [.height(260), .large],
            background: BSColor.Stage.surfaceRaised,
            fitsContent: true
        ) {
            VStack(spacing: BSSpacing.lg) {
                BSStageSheetHeader(
                    icon: "moon.stars",
                    title: "结束这场现场？",
                    subtitle: "确定这场已经结束了吗？",
                    tint: BSColor.Stage.liveTitle
                )

                HStack(spacing: 9) {
                    Button("还没有", action: onCancel)
                        .buttonStyle(BSSecondaryButtonStyle())

                    Button("结束现场", action: onConfirm)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.liveTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(BSColor.Stage.live.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .stroke(BSColor.Stage.live.opacity(0.34), lineWidth: 1)
                        )
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
}
