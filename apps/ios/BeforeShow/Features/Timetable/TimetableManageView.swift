import SwiftData
import SwiftUI

/// One place to manage the timetable's days and the selected day's stages.
/// Deletes confirm inside the row; nothing here stacks an alert.
struct TimetableManageView: View {
    let timetable: Timetable
    @Binding var selectedDayID: UUID
    @ObservedObject var coordinator: TimetableManagementCoordinator

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var newDate: Date
    @State private var newStageName = ""
    @State private var confirmingDeleteID: UUID?

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
            if let error = coordinator.dayManagementError {
                Text(error)
                    .font(BSFont.caption)
                    .foregroundStyle(TimetableStyle.attention)
                    .listRowBackground(Color.clear)
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
    }

    // MARK: - Rows

    private func dayRow(_ day: TimetableDay, number: Int) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
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
                    deleteButton(id: day.id)
                }
            }
            if confirmingDeleteID == day.id {
                inlineConfirm(
                    BSLocalization.format("删除第%d天和它的 %d 场演出？", number, day.performances.count),
                    onDelete: { delete(day) }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(TimetableStyle.pressSpring) { selectedDayID = day.id } }
        .moveDisabled(true)
    }

    private func stageRow(_ stage: TimetableStage, in day: TimetableDay) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                TimetableStageLight.marker(stage.sortOrder)
                    .fill(TimetableStageLight.color(stage.sortOrder))
                    .frame(width: 8, height: 8)
                TextField(BSLocalization.text("舞台名称"), text: nameBinding(for: stage))
                    .font(BSFont.body.weight(.semibold))
                    .submitLabel(.done)
                Text(BSLocalization.format("%d 场", stage.performances.count))
                    .font(BSFont.caption)
                    .foregroundStyle(TimetableStyle.muted)
                if day.stages.count > 1 {
                    deleteButton(id: stage.id)
                }
            }
            if confirmingDeleteID == stage.id {
                inlineConfirm(
                    stage.performances.isEmpty
                        ? BSLocalization.format("删除「%@」？", stage.name)
                        : BSLocalization.format("删除「%@」和它的 %d 场演出？", stage.name, stage.performances.count),
                    onDelete: { deleteStage(stage, from: day) }
                )
            }
        }
    }

    private func deleteButton(id: UUID) -> some View {
        Button {
            withAnimation(TimetableStyle.pressSpring) { confirmingDeleteID = confirmingDeleteID == id ? nil : id }
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(TimetableStyle.muted)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("删除"))
    }

    private func inlineConfirm(_ message: String, onDelete: @escaping () -> Void) -> some View {
        HStack {
            Text(message)
                .font(BSFont.caption)
                .foregroundStyle(TimetableStyle.now)
            Spacer()
            Button(BSLocalization.text("取消")) {
                withAnimation(TimetableStyle.pressSpring) { confirmingDeleteID = nil }
            }
            .buttonStyle(.plain)
            .foregroundStyle(TimetableStyle.muted)
            Button(BSLocalization.text("删除"), role: .destructive, action: onDelete)
                .buttonStyle(.plain)
                .foregroundStyle(TimetableStyle.now)
        }
        .font(BSFont.caption)
    }

    // MARK: - Bindings & actions

    private func dateBinding(for day: TimetableDay) -> Binding<Date> {
        Binding(get: { day.date }, set: { date in
            coordinator.updateDayDate(day, to: date, in: timetable, context: modelContext)
        })
    }

    /// Commits on every keystroke that leaves a non-empty name; an emptied field keeps the old name.
    private func nameBinding(for stage: TimetableStage) -> Binding<String> {
        Binding(get: { stage.name }, set: { name in
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            coordinator.renameStage(stage, to: name, context: modelContext)
        })
    }

    private func addDay() {
        let template = selectedDay ?? timetable.orderedDays.last
        guard let day = coordinator.addDay(date: newDate, to: timetable, template: template, context: modelContext) else { return }
        withAnimation(TimetableStyle.pressSpring) { selectedDayID = day.id }
        newDate = Self.dayAfterLast(in: timetable)
        confirmingDeleteID = nil
    }

    private func delete(_ day: TimetableDay) {
        guard coordinator.deleteDay(day, from: timetable, context: modelContext) else { return }
        withAnimation(TimetableStyle.pressSpring) {
            if selectedDayID == day.id, let next = timetable.orderedDays.first { selectedDayID = next.id }
            confirmingDeleteID = nil
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
        withAnimation(TimetableStyle.pressSpring) { confirmingDeleteID = nil }
    }

    private static func dayAfterLast(in timetable: Timetable) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        let lastDate = timetable.orderedDays.last?.date ?? calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate
    }
}
