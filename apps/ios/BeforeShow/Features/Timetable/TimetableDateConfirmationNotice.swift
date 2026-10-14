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

    private func formatDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.month, .day], from: date)
        return BSLocalization.format("%d月%d日", parts.month ?? 1, parts.day ?? 1)
    }

    private var timetableDateText: String {
        guard let first = timetable.orderedDays.first else { return "" }
        if timetable.orderedDays.count > 1, let last = timetable.orderedDays.last {
            return "\(formatDate(first.date)) ~ \(formatDate(last.date))"
        }
        return formatDate(first.date)
    }

    var body: some View {
        Group {
            if !timetable.matchesDates(of: show) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundStyle(TimetableStyle.attention)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BSLocalization.text("现场日期与时刻表不一致"))
                                .font(BSFont.body.weight(.semibold))
                                .foregroundStyle(TimetableStyle.foreground)
                            HStack(spacing: 12) {
                                Text(BSLocalization.format("现场演出：%@", formatDate(show.effectiveDate)))
                                Text(BSLocalization.format("时刻表排期：%@", timetableDateText))
                            }
                            .font(BSFont.caption)
                            .foregroundStyle(TimetableStyle.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: syncShowToTimetable) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.checkmark")
                                Text(BSLocalization.format("更新现场为时刻表排期 (%@)", timetableDateText))
                            }
                            .font(BSFont.caption.weight(.semibold))
                            .foregroundStyle(TimetableStyle.background)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(TimetableStyle.mine))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 12) {
                            Button(action: syncTimetableToShow) {
                                Text(BSLocalization.format("平移时刻表至 %@", formatDate(show.effectiveDate)))
                                    .font(BSFont.caption)
                                    .foregroundStyle(TimetableStyle.muted)
                            }
                            .buttonStyle(.plain)

                            if let onManage {
                                Text("·")
                                    .font(BSFont.caption)
                                    .foregroundStyle(TimetableStyle.muted)

                                Button(action: onManage) {
                                    Text(BSLocalization.text("手动调整天数…"))
                                        .font(BSFont.caption)
                                        .foregroundStyle(TimetableStyle.muted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(BSFont.caption)
                            .foregroundStyle(TimetableStyle.attention)
                    }
                }
                .padding(BSSpacing.md)
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
