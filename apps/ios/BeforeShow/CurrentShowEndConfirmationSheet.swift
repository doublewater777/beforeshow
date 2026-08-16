import SwiftUI

struct CurrentShowEndConfirmationSheet: View {
    private enum Step { case choice, earlier }

    let showName: String
    let showStart: Date
    let suggestedEnd: Date
    let calendar: Calendar
    let allowsJustEnded: Bool
    let onConfirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var selectedEnd: Date

    init(
        showName: String,
        showStart: Date,
        suggestedEnd: Date,
        calendar: Calendar,
        allowsJustEnded: Bool,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.showName = showName
        self.showStart = showStart
        self.suggestedEnd = suggestedEnd
        self.calendar = calendar
        self.allowsJustEnded = allowsJustEnded
        self.onConfirm = onConfirm
        let suggested = min(Date(), suggestedEnd)
        _selectedEnd = State(initialValue: max(showStart, suggested))
        _step = State(initialValue: allowsJustEnded ? .choice : .earlier)
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            if step == .choice {
                choice
            } else {
                earlierTime
            }
        }
        .interactiveDismissDisabled(false)
    }

    private var choice: some View {
        VStack(spacing: BSSpacing.lg) {
            BSStageSheetHeader(
                icon: "moon.stars",
                title: BSLocalization.text("确认已经散场？"),
                subtitle: BSLocalization.text("记录散场时间。"),
                tint: BSColor.Stage.liveTitle
            )

            HStack(spacing: 9) {
                Button("早就结束") { step = .earlier }
                    .buttonStyle(BSSecondaryButtonStyle())
                if allowsJustEnded {
                    Button("刚刚结束") { onConfirm(Date()) }
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
    }

    private var earlierTime: some View {
        VStack(spacing: BSSpacing.lg) {
            BSStageSheetHeader(
                icon: "clock",
                title: BSLocalization.text("补记散场时间"),
                subtitle: showName,
                tint: BSColor.Stage.accent
            )

            BSSurfacePanel {
                VStack(spacing: BSSpacing.sm) {
                    DatePicker(
                        "散场日期",
                        selection: $selectedEnd,
                        in: showStart...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "散场时间",
                        selection: $selectedEnd,
                        in: showStart...Date(),
                        displayedComponents: .hourAndMinute
                    )
                }
                .tint(BSColor.Stage.accent)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
            }

            HStack {
                Text("现场时长")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                Spacer()
                Text(durationText)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
            }

            HStack(spacing: 9) {
                Button("返回", action: handleEarlierBack)
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("确认这个时间") { onConfirm(selectedEnd) }
                    .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    nonisolated static func performEarlierBackAction(
        allowsJustEnded: Bool,
        showChoice: () -> Void,
        dismiss: () -> Void
    ) {
        if allowsJustEnded {
            showChoice()
        } else {
            dismiss()
        }
    }

    private func handleEarlierBack() {
        Self.performEarlierBackAction(
            allowsJustEnded: allowsJustEnded,
            showChoice: { step = .choice },
            dismiss: { dismiss() }
        )
    }

    private var durationText: String {
        let minutes = max(0, Int(selectedEnd.timeIntervalSince(showStart) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return BSLocalization.format("%lld 分", rest) }
        if rest == 0 { return BSLocalization.format("%lld 小时", hours) }
        return BSLocalization.format("%lld 小时 %lld 分", hours, rest)
    }
}
