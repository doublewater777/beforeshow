import SwiftUI

struct TimetableReviewExitNotice: View {
    let onContinue: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text("有未保存的修改"))
                .foregroundStyle(TimetableStyle.foreground)
            HStack {
                Button(BSLocalization.text("继续编辑"), action: onContinue)
                    .foregroundStyle(TimetableStyle.mine)
                Spacer()
                Button(BSLocalization.text("放弃修改"), role: .destructive, action: onDiscard)
                    .foregroundStyle(TimetableStyle.now)
            }
            .frame(minHeight: BSLayout.minTouchTarget)
        }
        .font(BSFont.caption)
        .buttonStyle(.plain)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSSpacing.sm)
        .background(TimetableStyle.card)
    }
}
