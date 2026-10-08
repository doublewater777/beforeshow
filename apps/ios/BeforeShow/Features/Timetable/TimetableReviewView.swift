import SwiftUI
import UIKit

/// Check and correct the recognized schedule. Suspicious rows are marked in
/// place; every fix happens inline in the row itself.
struct TimetableReviewView: View {
    @Binding var draft: TimetableDraft
    let originalThumbnail: UIImage?
    let avatarURL: (String) -> URL?
    @Binding var isOriginalVisible: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var dayIndex = 0
    @State private var editingID: UUID?
    @State private var renamingStageID: UUID?
    @State private var onlyIssues = false
    @FocusState private var focusedStageID: UUID?

    private var day: TimetableDraftDay? {
        draft.days.indices.contains(dayIndex) ? draft.days[dayIndex] : nil
    }

    private var timeZone: TimeZone { TimeZone(identifier: draft.timeZoneIdentifier) ?? .current }

    private var issues: [UUID: TimetableReviewIssues.Stage] {
        Dictionary(uniqueKeysWithValues: (day?.stages ?? []).map { ($0.id, TimetableReviewIssues.evaluate($0)) })
    }

    var body: some View {
        let issues = issues
        let issueCount = issues.values.reduce(0) { $0 + $1.count }
        VStack(spacing: 0) {
            header
            controls
            summary(issueCount: issueCount)
            list(issues: issues)
        }
        .background(TimetableStyle.background.ignoresSafeArea())
        .onChange(of: issueCount) { _, count in
            if count == 0 { onlyIssues = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(BSLocalization.text("取消"))
            Spacer()
            Text(BSLocalization.text("核对时刻表"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TimetableStyle.foreground)
            Spacer()
            Button(action: onSave) {
                Group {
                    if isSaving {
                        ProgressView().tint(TimetableStyle.background)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                    }
                }
                .foregroundStyle(TimetableStyle.background)
                .frame(width: 36, height: 36)
                .background(Circle().fill(TimetableStyle.foreground))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(TimetablePressStyle())
            .disabled(isSaving)
            .accessibilityLabel(BSLocalization.text("保存"))
        }
        .padding(.horizontal, 6)
    }

    private var controls: some View {
        HStack {
            if draft.days.count > 1 {
                TimetableDaySwitcher(items: dayItems, selection: dayBinding)
            }
            Spacer()
            if let originalThumbnail {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isOriginalVisible.toggle() }
                } label: {
                    Image(uiImage: originalThumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isOriginalVisible ? TimetableStyle.mine : Color.white.opacity(0.18), lineWidth: isOriginalVisible ? 2 : 1)
                        )
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(BSLocalization.text("原图对照"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func summary(issueCount: Int) -> some View {
        HStack {
            Text(BSLocalization.format("%d 舞台 · %d 场", day?.stages.count ?? 0, day?.stages.reduce(0) { $0 + $1.performances.count } ?? 0))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(TimetableStyle.muted)
            Spacer()
            if issueCount > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { onlyIssues.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Circle().frame(width: 6, height: 6)
                        Text(BSLocalization.format("%d 处待确认", issueCount))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(onlyIssues ? TimetableStyle.background : TimetableStyle.attention)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(onlyIssues ? TimetableStyle.attention : TimetableStyle.attention.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 46)
        .padding(.horizontal, 20)
    }

    // MARK: - List

    private func list(issues: [UUID: TimetableReviewIssues.Stage]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array((day?.stages ?? []).enumerated()), id: \.element.id) { stageIndex, stage in
                    let stageIssues = issues[stage.id] ?? .init()
                    let rows = stage.performances
                        .sorted { $0.startsAt < $1.startsAt }
                        .filter { !onlyIssues || stageIssues.flagged($0.id) || editingID == $0.id }
                    if !onlyIssues || !rows.isEmpty {
                        Section {
                            ForEach(rows) { perf in
                                if editingID == perf.id, let binding = performanceBinding(stageIndex: stageIndex, id: perf.id) {
                                    TimetableReviewEditor(
                                        performance: binding,
                                        avatarURL: avatarURL(perf.artistName),
                                        hasOverlap: stageIssues.overlapping.contains(perf.id),
                                        timeZone: timeZone,
                                        onDelete: { delete(perf.id) },
                                        onDone: { withAnimation(.snappy) { editingID = nil } }
                                    )
                                } else {
                                    row(perf, issues: stageIssues)
                                }
                            }
                            if !onlyIssues {
                                addButton(stageID: stage.id)
                            }
                        } header: {
                            stageHeader(stage, stageIndex: stageIndex)
                        }
                    }
                }
            }
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func stageHeader(_ stage: TimetableDraftStage, stageIndex: Int) -> some View {
        HStack(spacing: 8) {
            if renamingStageID == stage.id {
                TextField(BSLocalization.text("舞台名称"), text: stageNameBinding(stageIndex))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TimetableStyle.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: 170)
                    .background(RoundedRectangle(cornerRadius: 9).fill(TimetableStyle.card))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(TimetableStyle.mine.opacity(0.55)))
                    .focused($focusedStageID, equals: stage.id)
                    .submitLabel(.done)
                    .onSubmit { renamingStageID = nil }
                    .onChange(of: focusedStageID) { _, focused in
                        if focused != stage.id { renamingStageID = nil }
                    }
            } else {
                Button {
                    editingID = nil
                    renamingStageID = stage.id
                    focusedStageID = stage.id
                } label: {
                    HStack(spacing: 6) {
                        Text(stage.name)
                            .font(.system(size: 15, weight: .heavy))
                            .tracking(0.3)
                            .foregroundStyle(TimetableStyle.foreground)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TimetableStyle.dim)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("\(stage.performances.count)")
                .font(TimetableStyle.mono(12))
                .foregroundStyle(TimetableStyle.dim)
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .background(.bar)
    }

    private func row(_ perf: TimetableDraftPerformance, issues: TimetableReviewIssues.Stage) -> some View {
        let overlap = issues.overlapping.contains(perf.id)
        let invalid = issues.invalid.contains(perf.id)
        return Button {
            withAnimation(.snappy) {
                renamingStageID = nil
                editingID = perf.id
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TimetableTimeFormat.range(perf.startsAt, perf.endsAt, timeZone: timeZone))
                    .font(TimetableStyle.mono(13))
                    .foregroundStyle(overlap || invalid ? TimetableStyle.attention : TimetableStyle.muted)
                    .frame(width: 104, alignment: .leading)
                TimetableArtistAvatar(name: perf.artistName, url: avatarURL(perf.artistName), size: 28)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                Text(perf.artistName.isEmpty ? BSLocalization.text("艺人名称") : perf.artistName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(perf.artistName.isEmpty ? TimetableStyle.dim : TimetableStyle.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if overlap || invalid {
                    Circle()
                        .fill(TimetableStyle.attention)
                        .frame(width: 7, height: 7)
                        .shadow(color: TimetableStyle.attention.opacity(0.6), radius: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private func addButton(stageID: UUID) -> some View {
        Button {
            let id = draft.addPerformance(stageID: stageID)
            withAnimation(.snappy) { editingID = id }
        } label: {
            Label(BSLocalization.text("添加演出"), systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TimetableStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 22)
    }

    // MARK: - Bindings & actions

    private var dayItems: [TimetableDaySwitcher.Item] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return draft.days.enumerated().map { index, day in
            let parts = calendar.dateComponents([.month, .day], from: day.date)
            return .init(id: day.id, label: BSLocalization.format("第%d天", index + 1), date: "\(parts.month ?? 0)/\(parts.day ?? 0)")
        }
    }

    private var dayBinding: Binding<UUID> {
        Binding(
            get: { day?.id ?? UUID() },
            set: { id in
                dayIndex = draft.days.firstIndex { $0.id == id } ?? 0
                editingID = nil
                renamingStageID = nil
            }
        )
    }

    private func stageNameBinding(_ stageIndex: Int) -> Binding<String> {
        let dayIndex = dayIndex
        return Binding(
            get: { draft.days[dayIndex].stages[stageIndex].name },
            set: { draft.days[dayIndex].stages[stageIndex].name = $0 }
        )
    }

    private func performanceBinding(stageIndex: Int, id: UUID) -> Binding<TimetableDraftPerformance>? {
        let dayIndex = dayIndex
        guard let index = draft.days[dayIndex].stages[stageIndex].performances.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { draft.days[dayIndex].stages[stageIndex].performances[index] },
            set: { draft.days[dayIndex].stages[stageIndex].performances[index] = $0 }
        )
    }

    private func delete(_ id: UUID) {
        withAnimation(.snappy) {
            editingID = nil
            draft.removePerformance(id: id)
            dayIndex = min(dayIndex, max(draft.days.count - 1, 0))
        }
    }
}

/// Inline editor for one performance row.
private struct TimetableReviewEditor: View {
    @Binding var performance: TimetableDraftPerformance
    let avatarURL: URL?
    let hasOverlap: Bool
    let timeZone: TimeZone
    let onDelete: () -> Void
    let onDone: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
            TimetableArtistAvatar(name: performance.artistName, url: avatarURL, size: 32)
            TextField(BSLocalization.text("艺人名称"), text: $performance.artistName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TimetableStyle.foreground)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(nameFocused ? TimetableStyle.mine : Color.white.opacity(0.14))
                        .frame(height: 1)
                }
            }

            HStack(spacing: 8) {
                timePicker($performance.startsAt)
                Text("–").foregroundStyle(TimetableStyle.dim)
                timePicker($performance.endsAt)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TimetableStyle.now)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TimetableStyle.now.opacity(0.1)))
                }
                .buttonStyle(TimetablePressStyle())
                .accessibilityLabel(BSLocalization.text("删除"))
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TimetableStyle.background)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TimetableStyle.foreground))
                }
                .buttonStyle(TimetablePressStyle())
                .accessibilityLabel(BSLocalization.text("完成"))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TimetableStyle.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08)))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.scale(scale: 0.98).combined(with: .opacity))
    }

    private func timePicker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(hasOverlap ? TimetableStyle.attention : TimetableStyle.mine)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.timeZone, timeZone)
    }
}

/// Signals worth a second look after OCR: two sets on one stage at the same
/// time, an end before its start, or a missing name.
enum TimetableReviewIssues {
    struct Stage {
        var overlapping: Set<UUID> = []
        var invalid: Set<UUID> = []
        var count = 0

        func flagged(_ id: UUID) -> Bool { overlapping.contains(id) || invalid.contains(id) }
    }

    static func evaluate(_ stage: TimetableDraftStage) -> Stage {
        var result = Stage()
        let ordered = stage.performances.sorted { $0.startsAt < $1.startsAt }
        for (i, a) in ordered.enumerated() {
            if a.endsAt <= a.startsAt || a.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.invalid.insert(a.id)
                result.count += 1
            }
            for b in ordered[(i + 1)...] where b.startsAt < a.endsAt && a.startsAt < b.endsAt {
                result.overlapping.formUnion([a.id, b.id])
                result.count += 1
            }
        }
        return result
    }
}
