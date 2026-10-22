import SwiftData
import SwiftUI

struct TimetableDateConfirmationNotice: View {
    let timetable: Timetable
    let show: Show
    var onManage: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    private var timeZone: TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).month(.defaultDigits).day())
    }

    private var timetableDateText: String {
        guard let first = timetable.orderedDays.first else { return "" }
        if timetable.orderedDays.count > 1, let last = timetable.orderedDays.last {
            return "\(shortDate(first.date))–\(shortDate(last.date))"
        }
        return shortDate(first.date)
    }

    var body: some View {
        Group {
            if !timetable.matchesDates(of: show) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    HStack(spacing: 10) {
                        summary
                        Spacer(minLength: 4)
                        actions
                            .layoutPriority(1)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(BSFont.caption)
                            .foregroundStyle(TimetableStyle.attention)
                    }
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TimetableStyle.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(TimetableStyle.attention.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSpacing.xs)
            }
        }
        .task {
            if timetable.needsDateConfirmation && timetable.matchesDates(of: show) {
                confirm()
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 18))
                .foregroundStyle(TimetableStyle.attention)
            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.text("日期不一致"))
                    .font(BSFont.body.weight(.semibold))
                    .foregroundStyle(TimetableStyle.foreground)
                Text(BSLocalization.format("现场 %1$@ · 时刻表 %2$@", shortDate(show.effectiveDate), timetableDateText))
                    .font(BSFont.caption)
                    .foregroundStyle(TimetableStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: syncShowToTimetable) {
                Text(BSLocalization.text("以时刻表为准"))
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundStyle(TimetableStyle.background)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(TimetableStyle.foreground))
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: syncTimetableToShow) {
                    Label(BSLocalization.format("平移时刻表至 %@", shortDate(show.effectiveDate)), systemImage: "arrow.left.and.right")
                }
                if let onManage {
                    Button(action: onManage) {
                        Label(BSLocalization.text("手动调整天数…"), systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .fixedSize()
    }

    private func confirm() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            guard timetable.confirmDates(for: show) else { return }
            do {
                try modelContext.save()
                errorMessage = nil
                reconcileNotifications()
            } catch {
                modelContext.rollback()
                errorMessage = BSLocalization.text("操作失败，请重试")
            }
        }
    }

    private func syncTimetableToShow() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            do {
                try timetable.shift(toStartDate: show.effectiveDate, for: show)
                try modelContext.save()
                errorMessage = nil
                reconcileNotifications()
            } catch {
                modelContext.rollback()
                errorMessage = BSLocalization.text("操作失败，请重试")
            }
        }
    }

    private func syncShowToTimetable() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            show.alignDate(with: timetable)
            do {
                try modelContext.save()
                errorMessage = nil
                reconcileNotifications()
            } catch {
                modelContext.rollback()
                errorMessage = BSLocalization.text("操作失败，请重试")
            }
        }
    }

    private func reconcileNotifications() {
        let container = modelContext.container
        Task { await LocalNotificationCenter.shared.reconcilePortfolio(in: ModelContext(container)) }
    }
}
