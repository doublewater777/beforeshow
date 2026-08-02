import SwiftUI

struct CurrentShowEndConfirmationSheet: View {
    private enum Step { case choice, earlier }

    let showName: String
    let showStart: Date
    let suggestedEnd: Date
    let allowsJustEnded: Bool
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var step: Step = .choice
    @State private var selectedEnd: Date

    init(showName: String, showStart: Date, suggestedEnd: Date, allowsJustEnded: Bool, onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.showName = showName
        self.showStart = showStart
        self.suggestedEnd = suggestedEnd
        self.allowsJustEnded = allowsJustEnded
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let suggested = min(Date(), suggestedEnd)
        _selectedEnd = State(initialValue: max(showStart, suggested))
        _step = State(initialValue: allowsJustEnded ? .choice : .earlier)
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
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
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(BSColor.Stage.liveTitle)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.live.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("确认已经散场？")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text("记录散场时间，并计入现场记录。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }

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

            Button("还没结束", action: onCancel)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(minHeight: BSLayout.minTouchTarget)
        }
    }

    private var earlierTime: some View {
        VStack(spacing: BSSpacing.lg) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("补记散场时间")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(showName)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            BSGlassPanel {
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
                Button("返回") { step = .choice }
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("确认这个时间") { onConfirm(selectedEnd) }
                    .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private var durationText: String {
        let minutes = max(0, Int(selectedEnd.timeIntervalSince(showStart) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) 分" }
        if rest == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(rest) 分"
    }
}

