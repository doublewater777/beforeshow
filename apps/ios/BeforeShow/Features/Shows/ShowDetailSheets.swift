import SwiftUI
import SwiftData
import UIKit

struct PostponeShowSheet: View {
    @Binding var newDate: Date
    let calendar: Calendar
    let onUndated: () -> Void
    let onDated: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            BSStageSheetHeader(
                icon: "calendar.badge.clock",
                title: BSLocalization.text("延期演出"),
                subtitle: BSLocalization.text("选择这场演出目前的延期状态。"),
                tint: BSColor.Accent.warm
            )

            BSSurfacePanel {
                DatePicker(BSLocalization.text("新日期"), selection: $newDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(BSColor.Accent.violet)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
            }

            VStack(spacing: BSSpacing.sm) {
                Button(BSLocalization.text("日期待定"), action: onUndated)
                    .buttonStyle(BSSecondaryButtonStyle())
                Button(BSLocalization.text("按选择日期延期"), action: onDated)
                    .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }
}

struct ConfirmedEndTimeEditorSheet: View {
    let showName: String
    let showStart: Date
    let calendar: Calendar
    let hasConfirmedEnd: Bool
    @Binding var endTime: Date
    let onSave: () -> Void
    let onUndo: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(hasConfirmedEnd ? BSLocalization.text("修改散场时间") : BSLocalization.text("补记散场时间"))
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(showName)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            BSSurfacePanel {
                VStack(spacing: BSSpacing.sm) {
                    DatePicker(
                        BSLocalization.text("散场日期"),
                        selection: $endTime,
                        in: showStart...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        BSLocalization.text("散场时间"),
                        selection: $endTime,
                        in: showStart...Date(),
                        displayedComponents: .hourAndMinute
                    )
                }
                .tint(BSColor.Stage.accent)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
            }

            VStack(spacing: BSSpacing.sm) {
                Button(BSLocalization.text("保存散场时间"), action: onSave)
                    .buttonStyle(BSPrimaryButtonStyle())
                if hasConfirmedEnd {
                    Button(BSLocalization.text("撤销结束"), action: onUndo)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.liveTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(BSColor.Stage.live.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                }
            }
        }
    }
}
