import Foundation
import SwiftUI

// MARK: - Add Show Lifecycle Confirmation

struct PendingAddShowLifecycleConfirmation: Identifiable {
    let id = UUID()
    let show: Show
}

struct AddShowLifecycleConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let showName: String
    let showStart: Date
    let canConfirmEnd: Bool
    let calendar: Calendar
    let onLive: () -> Void
    let onEnded: (Date) -> Void

    @State private var isConfirmingEndTime = false
    @State private var endTime: Date

    init(
        showName: String,
        showStart: Date,
        canConfirmEnd: Bool,
        calendar: Calendar,
        now: Date = Date(),
        onLive: @escaping () -> Void,
        onEnded: @escaping (Date) -> Void
    ) {
        self.showName = showName
        self.showStart = showStart
        self.canConfirmEnd = canConfirmEnd
        self.calendar = calendar
        self.onLive = onLive
        self.onEnded = onEnded
        _endTime = State(initialValue: max(showStart, now))
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            if isConfirmingEndTime {
                BSStageSheetHeader(
                    icon: "clock",
                    title: BSLocalization.text("实际几点结束？"),
                    subtitle: showName,
                    tint: BSColor.Stage.accent
                )

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

                Button(BSLocalization.text("确认结束时间")) {
                    let confirmed = endTime
                    dismiss()
                    onEnded(confirmed)
                }
                .buttonStyle(BSPrimaryButtonStyle())
            } else {
                BSStageSheetHeader(
                    icon: "music.note",
                    title: BSLocalization.text("这场已经结束了吗？"),
                    subtitle: BSLocalization.text("我们看到这场已经开场，确认一下现在的状态。"),
                    tint: BSColor.Stage.accent
                )

                VStack(spacing: BSSpacing.sm) {
                    Button(BSLocalization.text("还在现场")) {
                        dismiss()
                        onLive()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())

                    if canConfirmEnd {
                        Button(BSLocalization.text("已经结束")) {
                            isConfirmingEndTime = true
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}
