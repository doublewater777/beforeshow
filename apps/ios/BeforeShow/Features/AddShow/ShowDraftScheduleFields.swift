import Foundation
import SwiftUI

// MARK: - Draft Schedule Fields

struct AddShowScheduleFields: View {
    @Binding var draft: ShowDraft
    @Binding var startTime: Date
    let isStartTimeConfirmed: Bool
    let onConfirmStartTime: () -> Void
    @Binding var hasEndTime: Bool
    @Binding var endDate: Date
    @Binding var endTime: Date
    /// 识别导入：开场日期标「已识别」薄荷绿描边。
    var dateRecognized: Bool = false
    /// 识别导入但日期是回退值（OCR 没读到日期）：金色「待确认」+ 确认按钮。
    var dateNeeded: Bool = false
    /// 识别导入：开场时间标「已识别」。
    var startTimeRecognized: Bool = false
    /// 日期回退值的确认回调：点确认按钮或手动改日期都会触发。
    var onConfirmFallbackDate: () -> Void = {}

    /// 两列瓷贴中间固定间距，不被中文长日期挤没。
    private static let columnSpacing: CGFloat = 14

    private var eventCalendar: Calendar { draft.timingCalendar() }
    private var endCalendar: Calendar { draft.endTimingCalendar() }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                AddShowDatePickerField(
                    title: BSLocalization.text("开场日期"),
                    selection: $draft.date,
                    displayedComponents: .date,
                    calendar: eventCalendar,
                    isRecognized: dateRecognized,
                    isNeeded: dateNeeded,
                    onConfirmNeeded: onConfirmFallbackDate
                )

                AddShowStartTimeField(
                    title: BSLocalization.text("开场时间"),
                    startTime: $startTime,
                    calendar: eventCalendar,
                    isConfirmed: isStartTimeConfirmed,
                    onConfirm: onConfirmStartTime,
                    isRecognized: startTimeRecognized
                )
            }

            AddShowEndTimeField(
                hasEndTime: $hasEndTime,
                endDate: $endDate,
                endTime: $endTime,
                calendar: endCalendar
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: hasEndTime)
    }
}

private struct AddShowConstrainedDatePicker: View {
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let calendar: Calendar
    var borderColor: Color? = nil

    private var displayText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageManager.persisted.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if displayedComponents == .hourAndMinute {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        }
        return formatter.string(from: selection)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            DatePicker("", selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .tint(BSColor.Accent.violet)
                .datePickerStyle(.compact)
                .padding(.leading, 16)

            Text(displayText)
                .font(BSFont.body)
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background {
                    BSColor.Stage.surface
                    Color.white.opacity(0.05)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(borderColor ?? BSColor.borderProminent, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }
}

private struct AddShowConfirmButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(AddShowConfirmButtonStyle())
            .accessibilityHint(BSLocalization.text("确认后才可以保存现场"))
    }
}

private struct AddShowConfirmButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(BSColor.Accent.violet.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .contentShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }
}

private struct AddShowDatePickerField: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let calendar: Calendar
    var isRequired = true
    var isRecognized = false
    var isNeeded = false
    /// isNeeded 时的确认回调：点按钮或手动改动选择器都算确认。
    var onConfirmNeeded: (() -> Void)? = nil

    private var borderColor: Color? {
        if isNeeded {
            return BSColor.Stage.accent.opacity(0.50)
        }
        return isRecognized ? BSColor.Accent.prepare.opacity(0.30) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: isRequired,
                mark: isNeeded ? .needed : (isRecognized ? .recognized : nil)
            )
            AddShowConstrainedDatePicker(
                selection: $selection,
                displayedComponents: displayedComponents,
                calendar: calendar,
                borderColor: borderColor
            )
            .onChange(of: selection) { _, _ in
                if isNeeded {
                    onConfirmNeeded?()
                }
            }
            if isNeeded, let onConfirmNeeded {
                AddShowConfirmButton(
                    title: BSLocalization.text("确认使用这个日期"),
                    action: onConfirmNeeded
                )
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddShowStartTimeField: View {
    let title: String
    @Binding var startTime: Date
    let calendar: Calendar
    let isConfirmed: Bool
    let onConfirm: () -> Void
    var isRecognized = false

    private var borderColor: Color? {
        if !isConfirmed {
            return BSColor.Stage.accent.opacity(0.50)
        }
        return isRecognized ? BSColor.Accent.prepare.opacity(0.30) : nil
    }

    /// 确认按钮直接亮出所选时间，点之前就知道在确认什么。
    private var confirmTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageManager.persisted.locale
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = calendar.timeZone
        return BSLocalization.format("确认 %@ 开场", formatter.string(from: startTime))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: true,
                mark: isConfirmed ? (isRecognized ? .recognized : nil) : .needed
            )
            AddShowConstrainedDatePicker(
                selection: $startTime,
                displayedComponents: .hourAndMinute,
                calendar: calendar,
                borderColor: borderColor
            )
            .onChange(of: startTime) { _, _ in
                // 与日期字段一致：手动转动选择器即视为确认。
                if !isConfirmed { onConfirm() }
            }
            if !isConfirmed {
                AddShowConfirmButton(title: confirmTitle, action: onConfirm)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: BSMotion.interface), value: isConfirmed)
    }
}

private struct AddShowEndTimeField: View {
    @Binding var hasEndTime: Bool
    @Binding var endDate: Date
    @Binding var endTime: Date
    let calendar: Calendar

    private static let columnSpacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .center, spacing: BSSpacing.sm) {
                Text("结束时间")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BSColor.textTertiary)
                Spacer(minLength: 0)
                Toggle("结束时间", isOn: $hasEndTime)
                    .labelsHidden()
                    .tint(BSColor.Accent.violet)
                    .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget)
            }

            if hasEndTime {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    AddShowDatePickerField(
                        title: BSLocalization.text("结束日期"),
                        selection: $endDate,
                        displayedComponents: .date,
                        calendar: calendar,
                        isRequired: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        AddShowFieldLabel(title: BSLocalization.text("结束时间"), isRequired: false)
                        AddShowConstrainedDatePicker(
                            selection: $endTime,
                            displayedComponents: .hourAndMinute,
                            calendar: calendar
                        )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
