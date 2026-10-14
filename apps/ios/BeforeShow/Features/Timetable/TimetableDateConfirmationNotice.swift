import SwiftData
import SwiftUI

struct TimetableDateConfirmationNotice: View {
    let timetable: Timetable
    let show: Show
    var onManage: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var saveFailed = false

    var body: some View {
        if timetable.needsDateConfirmation || !timetable.matchesDates(of: show) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text(BSLocalization.text(saveFailed ? "日期确认失败，请重试" : "现场日期已变化，请核对时刻表"))
                    .foregroundStyle(TimetableStyle.attention)
                if timetable.matchesDates(of: show) {
                    Button(BSLocalization.text("确认演出日期"), action: confirm)
                        .foregroundStyle(TimetableStyle.mine)
                } else if let onManage {
                    Button(BSLocalization.text("修改演出日期"), action: onManage)
                        .foregroundStyle(TimetableStyle.mine)
                }
            }
            .font(BSFont.caption)
            .buttonStyle(.plain)
            .padding(BSSpacing.roomy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TimetableStyle.card)
        }
    }

    private func confirm() {
        guard timetable.confirmDates(for: show) else { return }
        do {
            try modelContext.save()
            saveFailed = false
            let container = modelContext.container
            Task { await LocalNotificationCenter.shared.reconcilePortfolio(in: ModelContext(container)) }
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}
