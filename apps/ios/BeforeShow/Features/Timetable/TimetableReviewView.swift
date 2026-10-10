import SwiftUI
import UIKit

/// Check and correct the recognized schedule. Suspicious rows are marked in
/// place; every fix happens inline in the row itself.
struct TimetableReviewView: View {
    @Binding var draft: TimetableDraft
    let originalThumbnail: UIImage?
    let avatarURL: (String) -> URL?
    let artistLinker: TimetableArtistLinker
    @Binding var isOriginalVisible: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var session = TimetableReviewSession()
    @State private var renamingStageID: UUID?
    @State private var onlyIssues = false
    @State private var isConfirmingExit = false
    @State private var scrollRequest = 0
    @FocusState private var focusedStageID: UUID?

    private var day: TimetableDraftDay? {
        draft.days.indices.contains(session.dayIndex) ? draft.days[session.dayIndex] : nil
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
            summary(issueCount: totalIssueCount)
            if isConfirmingExit {
                TimetableReviewExitNotice(onContinue: { isConfirmingExit = false }, onDiscard: onCancel)
            }
            if let error = session.saveError, session.errorPerformanceID == nil, session.errorStageID == nil {
                Text(BSLocalization.text(TimetableReviewIssues.message(for: error)))
                    .font(BSFont.caption)
                    .foregroundStyle(TimetableStyle.attention)
                    .padding(BSSpacing.compact)
            }
            list(issues: issues)
        }
        .background(TimetableStyle.background.ignoresSafeArea())
        .onAppear { session.captureInitialDraft(draft) }
        .interactiveDismissDisabled()
        .onChange(of: draft) { _, _ in
            session.clearSaveError()
            isConfirmingExit = false
        }
        .onChange(of: issueCount) { _, count in
            if count == 0 { onlyIssues = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(BSLocalization.text("取消"))
            .disabled(isSaving)
            Spacer()
            Text(BSLocalization.text("核对时刻表"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TimetableStyle.foreground)
            Spacer()
            TimetableTextActionButton(title: BSLocalization.text("保存"), isLoading: isSaving, action: save)
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
                    withAnimation(.easeOut(duration: 0.25)) {
                        if !onlyIssues && issues.values.allSatisfy({ $0.count == 0 }),
                           let index = draft.days.firstIndex(where: { $0.stages.contains { TimetableReviewIssues.evaluate($0).count > 0 } }) {
                            session.finishEditing()
                            session.dayIndex = index
                        }
                        onlyIssues.toggle()
                    }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array((day?.stages ?? []).enumerated()), id: \.element.id) { stageIndex, stage in
                        let stageIssues = issues[stage.id] ?? .init()
                        let rows = session.orderedPerformances(in: stage)
                            .filter { !onlyIssues || stageIssues.hasInvalidName || stageIssues.flagged($0.id) || session.editingID == $0.id }
                        if !onlyIssues || !rows.isEmpty {
                            Section {
                                ForEach(rows) { perf in
                                    if session.editingID == perf.id, let binding = performanceBinding(stageIndex: stageIndex, id: perf.id) {
                                        TimetableReviewEditor(
                                            performance: binding,
                                            avatarURL: avatarURL(perf.artistName),
                                            artistLinker: artistLinker,
                                            hasOverlap: stageIssues.overlapping.contains(perf.id),
                                            saveError: session.errorPerformanceID == perf.id ? session.saveError : nil,
                                            timeZone: timeZone,
                                            onDelete: { delete(perf.id) },
                                            onDone: { withAnimation(.snappy) { session.finishEditing() } },
                                            onRevealArtistSearch: {
                                                withAnimation(.snappy) { proxy.scrollTo("artist-search-\(perf.id)", anchor: .center) }
                                            }
                                        )
                                        .id(perf.id)
                                    } else {
                                        row(perf, issues: stageIssues)
                                            .id(perf.id)
                                    }
                                }
                                if !onlyIssues {
                                    addButton(stageID: stage.id)
                                }
                            } header: {
                                stageHeader(stage, stageIndex: stageIndex)
                                    .id(stage.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: scrollRequest) {
                guard let id = session.editingID ?? session.errorStageID else { return }
                await Task.yield()
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func stageHeader(_ stage: TimetableDraftStage, stageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        session.finishEditing()
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
            if stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(BSLocalization.text("请输入舞台名称"))
                    .font(BSFont.caption)
                    .foregroundStyle(TimetableStyle.attention)
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.bottom, BSSpacing.sm)
            }
        }
        .background(.bar)
    }

    private func row(_ perf: TimetableDraftPerformance, issues: TimetableReviewIssues.Stage) -> some View {
        let overlap = issues.overlapping.contains(perf.id)
        let invalid = issues.invalid.contains(perf.id)
        return Button {
            withAnimation(.snappy) {
                renamingStageID = nil
                session.beginEditing(perf.id, in: draft)
                scrollRequest += 1
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TimetableTimeFormat.range(perf.startsAt, perf.endsAt, timeZone: timeZone))
                    .font(TimetableStyle.mono(13))
                    .foregroundStyle(overlap || invalid ? TimetableStyle.attention : TimetableStyle.muted)
                    .frame(width: 104, alignment: .leading)
                TimetableArtistAvatar(name: perf.artistName, url: perf.appleMusicArtistID == nil ? avatarURL(perf.artistName) : perf.artistAvatarURL.flatMap(URL.init(string:)), size: 28)
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
            withAnimation(.snappy) {
                session.beginEditing(id, in: draft)
                scrollRequest += 1
            }
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
            return .init(id: day.id, label: BSLocalization.format("第%d天", index + 1), date: "\(parts.month ?? 0)/\(parts.day ?? 0)", issueCount: day.stages.reduce(0) { $0 + TimetableReviewIssues.evaluate($1).count })
        }
    }

    private var dayBinding: Binding<UUID> {
        Binding(
            get: { day?.id ?? UUID() },
            set: { id in
                session.dayIndex = draft.days.firstIndex { $0.id == id } ?? 0
                session.finishEditing()
                renamingStageID = nil
            }
        )
    }

    private func stageNameBinding(_ stageIndex: Int) -> Binding<String> {
        let dayIndex = session.dayIndex
        return Binding(
            get: { draft.days[dayIndex].stages[stageIndex].name },
            set: { draft.days[dayIndex].stages[stageIndex].name = $0 }
        )
    }

    private func performanceBinding(stageIndex: Int, id: UUID) -> Binding<TimetableDraftPerformance>? {
        let dayIndex = session.dayIndex
        guard let index = draft.days[dayIndex].stages[stageIndex].performances.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { draft.days[dayIndex].stages[stageIndex].performances[index] },
            set: { draft.days[dayIndex].stages[stageIndex].performances[index] = $0 }
        )
    }

    private func save() {
        isConfirmingExit = false
        if session.prepareSave(draft) {
            onSave()
        } else {
            onlyIssues = false
            renamingStageID = session.errorStageID
            focusedStageID = session.errorStageID
            scrollRequest += 1
        }
    }

    private var totalIssueCount: Int {
        draft.days.flatMap(\.stages).reduce(0) { $0 + TimetableReviewIssues.evaluate($1).count }
    }

    private func cancel() {
        if session.hasChanges(in: draft) { isConfirmingExit = true }
        else { onCancel() }
    }

    private func delete(_ id: UUID) {
        withAnimation(.snappy) {
            session.finishEditing()
            draft.removePerformance(id: id)
            session.dayIndex = min(session.dayIndex, max(draft.days.count - 1, 0))
        }
    }
}
