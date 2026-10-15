import SwiftData
import SwiftUI

/// One place to manage the timetable's days and the selected day's stages.
/// Deletes confirm inside the row; nothing here stacks an alert.
struct TimetableManageView: View {
    let timetable: Timetable
    @Binding var selectedDayID: UUID
    var coordinator: TimetableManagementCoordinator

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var newDate: Date
    @State private var newStageName = ""
    @State private var deletionTarget: DeletionTarget?

    private enum DeletionTarget: Identifiable {
        case day(TimetableDay, number: Int)
        case stage(TimetableStage, day: TimetableDay)

        var id: String {
            switch self {
            case .day(let day, _): return "day-\(day.id.uuidString)"
            case .stage(let stage, _): return "stage-\(stage.id.uuidString)"
            }
        }
    }

    init(timetable: Timetable, selectedDayID: Binding<UUID>, coordinator: TimetableManagementCoordinator) {
        self.timetable = timetable
        _selectedDayID = selectedDayID
        self.coordinator = coordinator
        _newDate = State(initialValue: Self.dayAfterLast(in: timetable))
    }

    private var timeZone: TimeZone { TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current }
    private var selectedDay: TimetableDay? {
        timetable.orderedDays.first { $0.id == selectedDayID } ?? timetable.orderedDays.first
    }
    private var selectedDayNumber: Int {
        (timetable.orderedDays.firstIndex { $0.id == selectedDay?.id } ?? 0) + 1
    }

    var body: some View {
        List {
            if let show = timetable.show {
                TimetableDateConfirmationNotice(timetable: timetable, show: show)
                    .listRowBackground(Color.clear)
            }
            if let error = coordinator.dayManagementError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TimetableStyle.attention)
                    Text(error)
                        .font(BSFont.caption)
                        .foregroundStyle(TimetableStyle.foreground)
                    Spacer()
                    Button {
                        withAnimation(TimetableStyle.pressSpring) {
                            coordinator.dayManagementError = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TimetableStyle.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("关闭提示"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TimetableStyle.attention.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(TimetableStyle.attention.opacity(0.24), lineWidth: 1)
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Section(BSLocalization.text("天数")) {
                ForEach(Array(timetable.orderedDays.enumerated()), id: \.element.id) { index, day in
                    dayRow(day, number: index + 1)
                }
                HStack(spacing: BSSpacing.sm) {
                    Button(BSLocalization.text("添加一天"), systemImage: "plus", action: addDay)
                        .foregroundStyle(TimetableStyle.mine)
                    Spacer()
                    TimetableDateField(title: "", selection: $newDate, timeZone: timeZone)
                        .labelsHidden()
                }
                .moveDisabled(true)
            }

            if let day = selectedDay {
                Section(BSLocalization.format("舞台 · 第%d天", selectedDayNumber)) {
                    ForEach(day.orderedStages) { stage in
                        stageRow(stage, in: day)
                    }
                    .onMove { from, to in
                        var ids = day.orderedStages.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        coordinator.reorderStages(of: day, to: ids, context: modelContext)
                    }
                    HStack(spacing: BSSpacing.sm) {
                        TextField(BSLocalization.text("新舞台名称"), text: $newStageName)
                            .submitLabel(.done)
                            .onSubmit { addStage(to: day) }
                        Button(BSLocalization.text("添加舞台"), systemImage: "plus") { addStage(to: day) }
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(TimetableStyle.mine)
                            .disabled(newStageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .moveDisabled(true)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(TimetableStyle.background.ignoresSafeArea())
        .tint(TimetableStyle.mine)
        .navigationTitle(BSLocalization.text("管理时刻表"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(BSLocalization.text("完成")) { dismiss() }
                    .foregroundStyle(TimetableStyle.foreground)
            }
        }
        .onAppear { coordinator.dayManagementError = nil }
        .confirmationDialog(
            deletionTargetDialogTitle,
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible,
            actions: {
                if let target = deletionTarget {
                    Button(deletionActionTitle(for: target), role: .destructive) {
                        performDeletion(target)
                    }
                    Button(BSLocalization.text("取消"), role: .cancel) {
                        deletionTarget = nil
                    }
                }
            },
            message: {
                if let target = deletionTarget {
                    Text(deletionMessage(for: target))
                }
            }
        )
    }

    // MARK: - Deletion Helpers

    private var deletionTargetDialogTitle: String {
        guard let target = deletionTarget else { return "" }
        switch target {
        case .day(_, let number):
            return BSLocalization.format("删除第%d天？", number)
        case .stage(let stage, _):
            return BSLocalization.format("删除「%@」？", stage.name)
        }
    }

    private func deletionMessage(for target: DeletionTarget) -> String {
        switch target {
        case .day(let day, let number):
            return day.performances.isEmpty
                ? BSLocalization.format("确认删除第%d天吗？", number)
                : BSLocalization.format("将同时删除该天下的 %d 场演出，此操作不可撤销。", day.performances.count)
        case .stage(let stage, _):
            return stage.performances.isEmpty
                ? BSLocalization.format("确认删除舞台「%@」吗？", stage.name)
                : BSLocalization.format("将同时删除该舞台下的 %d 场演出，此操作不可撤销。", stage.performances.count)
        }
    }

    private func deletionActionTitle(for target: DeletionTarget) -> String {
        switch target {
        case .day(_, let number):
            return BSLocalization.format("删除第%d天", number)
        case .stage:
            return BSLocalization.text("删除舞台")
        }
    }

    private func performDeletion(_ target: DeletionTarget) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch target {
        case .day(let day, _):
            delete(day)
        case .stage(let stage, let day):
            deleteStage(stage, from: day)
        }
        deletionTarget = nil
    }

    // MARK: - Rows

    private func dayRow(_ day: TimetableDay, number: Int) -> some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.format("第%d天", number))
                .font(BSFont.headline)
                .foregroundStyle(day.id == selectedDay?.id ? TimetableStyle.mine : TimetableStyle.foreground)
            TimetableDateField(title: "", selection: dateBinding(for: day), timeZone: timeZone)
                .labelsHidden()
            Spacer()
            Text(BSLocalization.format("%d 场", day.performances.count))
                .font(BSFont.caption)
                .foregroundStyle(TimetableStyle.muted)
            if timetable.days.count > 1 {
                Button {
                    deletionTarget = .day(day, number: number)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(TimetableStyle.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("删除"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(TimetableStyle.pressSpring) { selectedDayID = day.id } }
        .moveDisabled(true)
    }

    private func stageRow(_ stage: TimetableStage, in day: TimetableDay) -> some View {
        TimetableManageStageRow(
            stage: stage,
            canDelete: day.stages.count > 1,
            onRequestDelete: {
                deletionTarget = .stage(stage, day: day)
            },
            onCommitRename: { newName in
                coordinator.renameStage(stage, to: newName, context: modelContext)
            }
        )
    }

    // MARK: - Bindings & actions

    private func dateBinding(for day: TimetableDay) -> Binding<Date> {
        Binding(get: { day.date }, set: { date in
            coordinator.updateDayDate(day, to: date, in: timetable, context: modelContext)
        })
    }

    private func addDay() {
        let template = selectedDay ?? timetable.orderedDays.last
        guard let day = coordinator.addDay(date: newDate, to: timetable, template: template, context: modelContext) else { return }
        withAnimation(TimetableStyle.pressSpring) { selectedDayID = day.id }
        newDate = Self.dayAfterLast(in: timetable)
    }

    private func delete(_ day: TimetableDay) {
        guard coordinator.deleteDay(day, from: timetable, context: modelContext) else { return }
        withAnimation(TimetableStyle.pressSpring) {
            if selectedDayID == day.id, let next = timetable.orderedDays.first { selectedDayID = next.id }
        }
    }

    private func addStage(to day: TimetableDay) {
        guard coordinator.addStage(named: newStageName, to: day, context: modelContext) else { return }
        newStageName = ""
    }

    private func deleteStage(_ stage: TimetableStage, from day: TimetableDay) {
        if stage.performances.contains(where: { $0.id == TimetablePreviewPlayer.shared.activePerformanceID }) {
            TimetablePreviewPlayer.shared.stop()
        }
        guard coordinator.deleteStage(stage, from: day, context: modelContext) else { return }
    }

    private static func dayAfterLast(in timetable: Timetable) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        let lastDate = timetable.orderedDays.last?.date ?? calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate
    }
}

// MARK: - Subviews

private struct TimetableManageStageRow: View {
    let stage: TimetableStage
    let canDelete: Bool
    let onRequestDelete: () -> Void
    let onCommitRename: (String) -> Void

    @State private var draftName: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            TimetableStageLight.marker(stage.sortOrder)
                .fill(TimetableStageLight.color(stage.sortOrder))
                .frame(width: 8, height: 8)
            TextField(BSLocalization.text("舞台名称"), text: $draftName)
                .font(BSFont.body.weight(.semibold))
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit {
                    commitRename()
                }
            Text(BSLocalization.format("%d 场", stage.performances.count))
                .font(BSFont.caption)
                .foregroundStyle(TimetableStyle.muted)
            if canDelete {
                Button(action: onRequestDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(TimetableStyle.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("删除"))
            }
        }
        .onAppear {
            draftName = stage.name
        }
        .onChange(of: stage.name) { _, newName in
            if !isFocused {
                draftName = newName
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitRename()
            }
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftName = stage.name
        } else if trimmed != stage.name {
            onCommitRename(trimmed)
        }
    }
}


