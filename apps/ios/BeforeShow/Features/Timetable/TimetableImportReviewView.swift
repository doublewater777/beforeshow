import SwiftData
import SwiftUI

/// Review of an imported timetable on the regular stage matrix. Every edit
/// lands in the session's own store; nothing is saved before the checkmark.
struct TimetableImportReviewView: View {
    let session: TimetableImportSession
    @ObservedObject var coordinator: TimetableManagementCoordinator
    let linker: TimetableArtistLinker
    let avatarURL: (TimetablePerformance) -> URL?
    var onOpenOriginal: (() -> Void)? = nil
    var hasExistingTimetable: Bool = false
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var isManaging = false
    @State private var isConfirmingOverwrite = false

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
        .safeAreaInset(edge: .top) {
            reviewBanner
        }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if coordinator.isSaving {
                    ProgressView()
                } else {
                    if let onOpenOriginal {
                        Button(action: onOpenOriginal) {
                            Image(systemName: "photo")
                                .foregroundColor(BSColor.textSecondary)
                        }
                        .accessibilityLabel(BSLocalization.text("查看原图"))
                    }
                    Button(action: handleSaveTap) {
                        Image(systemName: "checkmark")
                            .foregroundColor(BSColor.textPrimary)
                    }
                    .accessibilityLabel(BSLocalization.text("确认保存"))
                }
            }
        }
        .confirmationDialog(
            BSLocalization.text("覆盖现有时刻表？"),
            isPresented: $isConfirmingOverwrite,
            titleVisibility: .visible
        ) {
            Button(BSLocalization.text("覆盖并保存"), role: .destructive) {
                onSave()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("这场现场已有一份时刻表，保存将替换现有的全部舞台与演出数据。"))
        }
        .navigationDestination(isPresented: $isManaging) {
            TimetableManageView(timetable: session.timetable, selectedDayID: dayBinding, coordinator: coordinator)
                .modelContainer(session.container)
        }
        .modelContainer(session.container)
    }

    private var reviewBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TimetableStyle.mine)

            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.text("排期预览中"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)

                Text(session.carriedOverInterestedCount > 0
                    ? BSLocalization.format("已为你保留 %d 场想看演出，请核对后保存", session.carriedOverInterestedCount)
                    : BSLocalization.text("核对舞台与时间无误后，轻点右上角确认保存"))
                    .font(.system(size: 11))
                    .foregroundStyle(TimetableStyle.dim)
            }

            Spacer(minLength: 0)

            if let onOpenOriginal {
                Button(action: onOpenOriginal) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text(BSLocalization.text("对照原图"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TimetableStyle.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(TimetablePressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func handleSaveTap() {
        if hasExistingTimetable {
            isConfirmingOverwrite = true
        } else {
            onSave()
        }
    }
}
