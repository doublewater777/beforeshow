import SwiftUI

enum CurrentShowEndConfirmationIntent {
    case justEnded
    case backfill
}

struct CurrentShowEndConfirmationSheet: View {
    private enum Step { case choice, earlier }

    let showName: String
    let showStart: Date
    let suggestedEnd: Date
    let calendar: Calendar
    let allowsJustEnded: Bool
    let onConfirm: (Date, CurrentShowEndConfirmationIntent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var selectedEnd: Date
    @State private var justEndedFeedback = 0

    init(
        showName: String,
        showStart: Date,
        suggestedEnd: Date,
        calendar: Calendar,
        allowsJustEnded: Bool,
        onConfirm: @escaping (Date, CurrentShowEndConfirmationIntent) -> Void
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
                title: BSLocalization.text("散场了？"),
                subtitle: showName,
                tint: BSColor.Stage.liveTitle
            )

            HStack(spacing: 9) {
                Button("补记散场时间") { step = .earlier }
                    .buttonStyle(BSSecondaryButtonStyle())
                if allowsJustEnded {
                    Button {
                        justEndedFeedback += 1
                        onConfirm(Date(), .justEnded)
                    } label: {
                        Text("刚刚散场")
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
                            .contentShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: justEndedFeedback)
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
                Button("确认这个时间") { onConfirm(selectedEnd, .backfill) }
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
        return ShowDurationFormatter.single(totalMinutes: minutes)
    }
}
