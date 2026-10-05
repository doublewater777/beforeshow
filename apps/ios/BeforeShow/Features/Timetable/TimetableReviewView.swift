import SwiftUI

struct TimetableReviewView: View {
    @Binding var draft: TimetableDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var selectedDayIndex = 0
    @State private var editingPerformanceID: UUID?
    @State private var editingArtistName = ""
    @State private var editingStartsAt = Date()
    @State private var editingEndsAt = Date()

    @State private var editingStageID: UUID?
    @State private var editingStageName = ""
    @State private var isEditingStagePresented = false

    private var summary: TimetableDraftSummary { draft.summary }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BSSpacing.lg) {
                    summaryCard
                    if draft.days.count > 1 {
                        dayPicker
                    }
                    if draft.days.indices.contains(selectedDayIndex) {
                        dayStagesView(day: draft.days[selectedDayIndex])
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, 120)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert(BSLocalization.text("修改舞台名称"), isPresented: $isEditingStagePresented) {
            TextField(BSLocalization.text("舞台名称"), text: $editingStageName)
            Button(BSLocalization.text("确定")) {
                if let sID = editingStageID {
                    draft.updateStageName(stageID: sID, newName: editingStageName)
                }
                editingStageID = nil
            }
            Button(BSLocalization.text("取消"), role: .cancel) {
                editingStageID = nil
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button(action: onCancel) {
                Text(BSLocalization.text("取消"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
            }
            Spacer()
            Text(BSLocalization.text("检查时刻表"))
                .font(BSFont.headline)
                .foregroundColor(BSColor.textPrimary)
            Spacer()
            Button(action: onSave) {
                Text(BSLocalization.text("保存"))
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Accent.warm)
            }
        }
        .padding(.horizontal, BSSpacing.lg)
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.sm)
    }

    private var summaryCard: some View {
        HStack(spacing: BSSpacing.md) {
            summaryItem(
                title: BSLocalization.text("日期"),
                value: summary.dateRangeDescription.isEmpty ? "-" : summary.dateRangeDescription,
                icon: "calendar"
            )
            Divider().frame(height: 32).overlay(Color.white.opacity(0.12))
            summaryItem(
                title: BSLocalization.text("舞台数"),
                value: "\(summary.stageCount)",
                icon: "music.mic"
            )
            Divider().frame(height: 32).overlay(Color.white.opacity(0.12))
            summaryItem(
                title: BSLocalization.text("演出数"),
                value: "\(summary.performanceCount)",
                icon: "guitars"
            )
        }
        .padding(.vertical, BSSpacing.md)
        .padding(.horizontal, BSSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(BSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.textTertiary)
                Text(title)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(BSColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.days.indices, id: \.self) { idx in
                    let day = draft.days[idx]
                    let isSelected = idx == selectedDayIndex
                    Button {
                        selectedDayIndex = idx
                    } label: {
                        Text(formatDayTab(day.date))
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .black : BSColor.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color.white : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func dayStagesView(day: TimetableDraftDay) -> some View {
        VStack(spacing: BSSpacing.lg) {
            ForEach(day.stages) { stage in
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    HStack {
                        Label(stage.name, systemImage: "music.mic")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.Accent.warm)

                        Spacer()

                        Button {
                            editingStageID = stage.id
                            editingStageName = stage.name
                            isEditingStagePresented = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(BSColor.textTertiary)
                                .padding(6)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(stage.performances) { perf in
                            performanceRow(perf: perf, dayDate: day.date)
                        }
                    }
                }
                .padding(BSSpacing.md)
                .background(BSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private func performanceRow(perf: TimetableDraftPerformance, dayDate: Date) -> some View {
        let isEditing = editingPerformanceID == perf.id

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimeRange(start: perf.startsAt, end: perf.endsAt))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(BSColor.Accent.prepare)
                    Text(perf.artistName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if isEditing {
                            saveInlineEdit(for: perf.id)
                        } else {
                            startInlineEdit(perf: perf)
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(isEditing ? BSColor.Accent.warm : BSColor.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }

                    Button {
                        withAnimation(.snappy) {
                            draft.removePerformance(id: perf.id)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(Color.red.opacity(0.75))
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.10))
                            .clipShape(Circle())
                    }
                }
            }

            if isEditing {
                VStack(spacing: 10) {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Text(BSLocalization.text("艺人"))
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                            .frame(width: 44, alignment: .leading)
                        TextField(BSLocalization.text("艺人名称"), text: $editingArtistName)
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        Text(BSLocalization.text("时间"))
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                            .frame(width: 44, alignment: .leading)
                        DatePicker("", selection: $editingStartsAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("-")
                            .foregroundColor(BSColor.textTertiary)
                        DatePicker("", selection: $editingEndsAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(isEditing ? 0.05 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button(action: onSave) {
                Label(BSLocalization.text("保存时刻表"), systemImage: "checkmark")
            }
            .buttonStyle(BSPrimaryButtonStyle())
        }
        .padding(.horizontal, BSSpacing.lg)
        .padding(.vertical, BSSpacing.md)
        .background(
            Color.black.opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func startInlineEdit(perf: TimetableDraftPerformance) {
        editingPerformanceID = perf.id
        editingArtistName = perf.artistName
        editingStartsAt = perf.startsAt
        editingEndsAt = perf.endsAt
    }

    private func saveInlineEdit(for id: UUID) {
        var end = editingEndsAt
        if end <= editingStartsAt {
            end = Calendar.current.date(byAdding: .minute, value: 45, to: editingStartsAt) ?? editingStartsAt.addingTimeInterval(2700)
        }
        draft.updatePerformance(
            id: id,
            artistName: editingArtistName.isEmpty ? "未知艺人" : editingArtistName,
            startsAt: editingStartsAt,
            endsAt: end
        )
        editingPerformanceID = nil
    }

    private func formatDayTab(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}
