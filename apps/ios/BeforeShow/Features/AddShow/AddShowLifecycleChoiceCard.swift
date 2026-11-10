import Foundation
import SwiftUI

// MARK: - Add Show Lifecycle Choice

/// 开场时间已过、系统判断不了这场是否已结束时，在表单里就地问一次，
/// 不在点保存后再叠一层 sheet。
struct AddShowLifecycleQuestion: Equatable {
    let minimumEnd: Date
    let endCalendar: Calendar

    static func resolve(for draft: ShowDraft, now: Date = Date()) -> Self? {
        guard draft.startTime != nil,
              let show = try? draft.makeShow(),
              AddShowLifecyclePolicy.resolution(for: show, now: now) == .needsEndConfirmation,
              // 还不可能已经结束时只能是正在进行，不必问。
              AddShowLifecyclePolicy.canConfirmEnd(for: show, now: now, calendar: show.timingCalendar())
        else { return nil }
        return Self(
            minimumEnd: AddShowLifecyclePolicy.minimumEndTime(for: show, calendar: show.timingCalendar()),
            endCalendar: show.endTimingCalendar()
        )
    }
}

extension AddShowLifecycleQuestion {
    /// 默认按开场后约 3 小时散场，不晚于现在。
    func defaultEnd(now: Date = Date()) -> Date {
        max(minimumEnd, min(now, minimumEnd.addingTimeInterval(3 * 3600)))
    }
}

enum AddShowLifecycleChoice: Equatable {
    case live
    case ended
}

struct AddShowLifecycleChoiceCard: View {
    let question: AddShowLifecycleQuestion
    @Binding var choice: AddShowLifecycleChoice?
    @Binding var endTime: Date

    var body: some View {
        EditShowFormCard(
            title: BSLocalization.text("这场已经开场了"),
            icon: "music.note",
            tint: BSColor.Stage.accent
        ) {
            HStack(spacing: BSSpacing.compact) {
                option(BSLocalization.text("还在现场"), value: .live)
                option(BSLocalization.text("已经结束"), value: .ended)
            }

            if choice == .ended {
                VStack(spacing: BSSpacing.sm) {
                    DatePicker(
                        BSLocalization.text("散场日期"),
                        selection: $endTime,
                        in: question.minimumEnd...max(question.minimumEnd, Date()),
                        displayedComponents: .date
                    )
                    DatePicker(
                        BSLocalization.text("散场时间"),
                        selection: $endTime,
                        in: question.minimumEnd...max(question.minimumEnd, Date()),
                        displayedComponents: .hourAndMinute
                    )
                }
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.muted)
                .tint(BSColor.Stage.foreground)
                .environment(\.calendar, question.endCalendar)
                .environment(\.timeZone, question.endCalendar.timeZone)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: BSMotion.interface), value: choice)
    }

    private func option(_ title: String, value: AddShowLifecycleChoice) -> some View {
        let isSelected = choice == value
        return Button {
            choice = value
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? BSColor.Stage.background : BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? BSColor.Stage.foreground : BSColor.Stage.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: BSRadius.md)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .strokeBorder(BSColor.Stage.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
