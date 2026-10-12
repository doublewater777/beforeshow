import SwiftData
import SwiftUI

/// Review of an imported timetable on the regular stage matrix. Every edit
/// lands in the session's own store; nothing is saved before the checkmark.
struct TimetableImportReviewView: View {
    let session: TimetableImportSession
    @ObservedObject var coordinator: TimetableManagementCoordinator
    let linker: TimetableArtistLinker
    let avatarURL: (TimetablePerformance) -> URL?
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var isManaging = false

    private var timeZone: TimeZone {
        TimeZone(identifier: session.timetable.timeZoneIdentifier) ?? .current
    }

    private var dayBinding: Binding<UUID> {
        Binding(
            get: {
                let days = session.timetable.orderedDays
                return days.contains { $0.id == session.selectedDayID } ? session.selectedDayID : (days.first?.id ?? UUID())
            },
            set: { session.selectedDayID = $0 }
        )
    }

    var body: some View {
        TimetableExperienceView(
            timetable: session.timetable,
            show: nil,
            selectedDayID: dayBinding,
            linker: linker,
            avatarURL: avatarURL,
            onManage: { isManaging = true },
            allowsSharing: false
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundColor(BSColor.textSecondary)
                }
                .disabled(coordinator.isSaving)
                .accessibilityLabel(BSLocalization.text("取消"))
            }
            if session.timetable.days.count > 1 {
                ToolbarItem(placement: .principal) {
                    TimetableDaySwitcher(
                        items: TimetableDayItems.make(session.timetable.orderedDays, timeZone: timeZone),
                        selection: dayBinding
                    )
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if coordinator.isSaving {
                    ProgressView()
                } else {
                    Button(action: onSave) {
                        Image(systemName: "checkmark")
                            .foregroundColor(BSColor.textPrimary)
                    }
                    .accessibilityLabel(BSLocalization.text("确认保存"))
                }
            }
        }
        .navigationDestination(isPresented: $isManaging) {
            TimetableManageView(timetable: session.timetable, selectedDayID: dayBinding, coordinator: coordinator)
                .modelContainer(session.container)
        }
        .modelContainer(session.container)
    }
}
