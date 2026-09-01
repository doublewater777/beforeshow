import Foundation
import SwiftUI

// MARK: - Show Draft Editor

enum ShowDraftEditorExitPolicy {
    static func requiresDiscardConfirmation(current: ShowDraft, initial: ShowDraft) -> Bool {
        current != initial
    }
}

struct ShowStatusActionResult {
    let tone: BSToastTone
    let message: String
}

struct ShowStatusEditingContext {
    let changeStatus: ShowChangeStatus
    let postponedDate: Date?
    let title: String
    let description: String
    let restoreTitle: String
    let onRestore: @MainActor () async -> ShowStatusActionResult
    let onPostpone: @MainActor (Date?) async -> ShowStatusActionResult
    let onCancel: @MainActor () async -> ShowStatusActionResult
    let onDelete: @MainActor () async -> Void
}

struct ShowDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveTitle: String
    /// 摘要卡右上角的状态胶囊文案（如「即将开场」「已延期」），nil 则不显示。
    var statusPillText: String? = nil
    /// 延期现场：摘要卡下方追加紫金横幅，说明这里编辑的是原定信息。
    var isPostponed: Bool = false
    /// 现场状态管理（延期 / 取消 / 恢复 / 删除），nil 时不渲染现场状态卡。
    var statusEditing: ShowStatusEditingContext? = nil
    let onSave: @MainActor (ShowDraft) async throws -> Void
    private let initialDraft: ShowDraft
    private let originalCoverURL: String

    @State private var draft: ShowDraft
    @State private var message: String?
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false
    @State private var coverLifecycle = ShowCoverLifecycle()
    @State private var didSave = false
    @State private var postponeDate = Date()
    @State private var showsPostponeSheet = false
    @State private var showsCancelConfirm = false
    @State private var showsDeleteConfirm = false
    @State private var isApplyingStatus = false
    @State private var statusToast: BSToastPayload?
    /// 编辑现场时无 import 流程,这个 binding 留空集合即可。
    @State private var userEditedFields: Set<ShowDraftField> = []
    private let artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()

    init(
        title: String,
        draft: ShowDraft,
        saveTitle: String,
        statusPillText: String? = nil,
        isPostponed: Bool = false,
        statusEditing: ShowStatusEditingContext? = nil,
        onSave: @escaping @MainActor (ShowDraft) async throws -> Void
    ) {
        self.title = title
        _draft = State(initialValue: draft)
        self.saveTitle = saveTitle
        self.statusPillText = statusPillText
        self.isPostponed = isPostponed
        self.statusEditing = statusEditing
        self.onSave = onSave
        initialDraft = draft
        originalCoverURL = draft.coverImageURL
    }

    private var hasUnsavedChanges: Bool {
        ShowDraftEditorExitPolicy.requiresDiscardConfirmation(current: draft, initial: initialDraft)
    }

    private var isEndTimeRangeValid: Bool {
        draft.startTime == nil || draft.hasValidEndTime()
    }

    var body: some View {
        NavigationStack {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        editorSummaryCard
                        if isPostponed {
                            postponedBanner
                        }

                        ShowDraftFormFields(
                            draft: $draft,
                            onCoverImported: { coverLifecycle.register(previous: $0, new: $1) },
                            artistSearch: artistSearch,
                            userEditedFields: $userEditedFields
                        )

                        if let statusEditing {
                            statusCard(statusEditing)
                            deleteShowEntry
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                saveBar
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, AppLanguageManager.persisted.locale)
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving || isApplyingStatus)
        .onChange(of: draft) { _, _ in
            message = nil
        }
        .sheet(isPresented: $showsPostponeSheet) {
            PostponeShowSheet(
                newDate: $postponeDate,
                calendar: draft.timingCalendar(),
                onUndated: {
                    showsPostponeSheet = false
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(nil) }
                    }
                },
                onDated: {
                    showsPostponeSheet = false
                    let newDate = ShowDateSelectionPolicy.normalizedDay(
                        postponeDate,
                        calendar: draft.timingCalendar()
                    )
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(newDate) }
                    }
                }
            )
        }
        .alert(
            DangerConfirmation.cancelShowFromEditor.title,
            isPresented: $showsCancelConfirm
        ) {
            Button(DangerConfirmation.cancelShowFromEditor.confirmTitle, role: .destructive) {
                Task { @MainActor in
                    await applyStatusAction { await statusEditing?.onCancel() }
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.cancelShowFromEditor.message)
        }
        .alert(
            DangerConfirmation.deleteShowFromEditor.title,
            isPresented: $showsDeleteConfirm
        ) {
            Button(DangerConfirmation.deleteShowFromEditor.confirmTitle, role: .destructive) {
                Task { @MainActor in
                    await statusEditing?.onDelete()
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.deleteShowFromEditor.message)
        }
        .bsToastOverlay(statusToast, bottomPadding: 96)
        .alert("放弃修改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                coverLifecycle.cancel()
                dismiss()
            }
        } message: {
            Text("尚未保存的现场信息会丢失。")
        }
        .onDisappear {
            guard !didSave else { return }
            coverLifecycle.cancel()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            BSChromeToolbarCloseButton(accessibilityLabel: "取消编辑") { requestDismiss() }
        }
        }
    }

    private func requestDismiss() {
        dismissKeyboard()
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            coverLifecycle.cancel()
            dismiss()
        }
    }

    // MARK: - 摘要卡：滚动时始终知道在编辑哪一场

    private var editorSummaryCard: some View {
        HStack(spacing: 14) {
            ShowCoverImageView(
                urlString: draft.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                cornerRadius: 10
            )
            .frame(width: 45, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名现场" : draft.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(2)

                Text(summaryDateText)
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let statusPillText {
                editorStatusPill(text: statusPillText)
            }
        }
        .padding(14)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private var summaryDateText: String {
        let calendar = draft.timingCalendar()
        let locale = AppLanguageManager.persisted.locale
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale)
        dateFormatter.timeZone = calendar.timeZone
        var text = (isPostponed ? BSLocalization.text("原定 ") : "") + dateFormatter.string(from: draft.date)
        if let startTime = draft.startTime {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = locale
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = calendar.timeZone
            text += " " + timeFormatter.string(from: startTime)
        }
        let venue = draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            text += " · \(venue)"
        }
        return text
    }

    private func editorStatusPill(text: String) -> some View {
        let tint = isPostponed
            ? Color(red: 0.84, green: 0.76, blue: 1.0)
            : BSColor.Stage.accent
        return HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
    }

    // MARK: - 延期横幅

    private var postponedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Accent.violet)

            Text("这场已延期。这里编辑的是原定信息；延期日期在下方「现场状态」中更新。")
                .font(.system(size: 12.5))
                .foregroundColor(Color(red: 0.80, green: 0.74, blue: 0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.violet.opacity(0.12),
                    BSColor.Stage.accent.opacity(0.07)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.violet.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - 现场状态卡（并入编辑现场，操作立即生效）

    private func statusTint(for status: ShowChangeStatus) -> Color {
        switch status {
        case .scheduled: return BSColor.Accent.prepare
        case .postponed: return Color(red: 0.84, green: 0.76, blue: 1.0)
        case .canceled: return BSColor.Accent.danger
        }
    }

    private func statusIconName(for status: ShowChangeStatus) -> String {
        switch status {
        case .scheduled: return "checkmark.circle.fill"
        case .postponed: return "calendar.badge.clock"
        case .canceled: return "xmark.circle.fill"
        }
    }

    private func statusCard(_ context: ShowStatusEditingContext) -> some View {
        let tint = statusTint(for: context.changeStatus)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.13))
                    Image(systemName: statusIconName(for: context.changeStatus))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 26, height: 26)

                Text("现场状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)

                Spacer(minLength: 0)

                Text(context.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.30), lineWidth: 1)
                    )
            }

            Text(context.description)
                .font(.system(size: 12.5))
                .foregroundColor(BSColor.textTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if context.changeStatus != .scheduled {
                    Button {
                        Task { @MainActor in
                            await applyStatusAction { await statusEditing?.onRestore() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BSColor.textTertiary)
                            Text(context.restoreTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(BSColor.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplyingStatus)
                    .accessibilityLabel(context.restoreTitle)
                }

                if context.changeStatus != .canceled {
                    HStack(spacing: 12) {
                        statusActionButton(
                            title: context.changeStatus == .postponed ? "更新延期信息" : "记录延期",
                            systemImage: "calendar.badge.clock",
                            tint: Color(red: 0.84, green: 0.76, blue: 1.0)
                        ) {
                            postponeDate = context.postponedDate ?? draft.date
                            showsPostponeSheet = true
                        }

                        statusActionButton(
                            title: BSLocalization.text("记录取消"),
                            systemImage: "xmark.circle",
                            tint: BSColor.Accent.danger
                        ) {
                            showsCancelConfirm = true
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func statusActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(tint.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isApplyingStatus)
        .accessibilityLabel(title)
    }

    private var deleteShowEntry: some View {
        Button {
            showsDeleteConfirm = true
        } label: {
            Text("删除现场")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(BSColor.Accent.danger.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isApplyingStatus)
        .accessibilityLabel("删除现场")
    }

    @MainActor
    private func applyStatusAction(
        _ action: @MainActor () async -> ShowStatusActionResult?
    ) async {
        guard !isApplyingStatus else { return }
        isApplyingStatus = true
        let result = await action()
        isApplyingStatus = false
        if let result {
            presentStatusToast(result.tone, message: result.message)
        }
    }

    private func presentStatusToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        statusToast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if statusToast == payload {
                statusToast = nil
            }
        }
    }

    // MARK: - 吸底保存栏

    private var saveBar: some View {
        VStack(spacing: 10) {
            saveBarStatus
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

            Button {
                Task { @MainActor in
                    await save()
                }
            } label: {
                HStack(spacing: BSSpacing.sm) {
                    if isSaving {
                        ProgressView()
                            .tint(Color(red: 0.15, green: 0.11, blue: 0.04))
                    }
                    Text(isSaving ? "正在保存" : saveTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(!draft.isReadyToSave || isSaving)
            .accessibilityLabel(isSaving ? "正在保存" : saveTitle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var saveBarStatus: some View {
        if let message {
            Text(message)
                .foregroundColor(BSColor.Accent.danger)
        } else if !isEndTimeRangeValid {
            Text("结束时间需晚于开始时间，请修正后保存")
                .foregroundColor(BSColor.Stage.muted)
        } else if hasUnsavedChanges {
            HStack(spacing: 7) {
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: BSColor.Stage.accent.opacity(0.7), radius: 4)
                Text("有未保存的修改")
                    .foregroundColor(BSColor.Stage.muted)
            }
        } else {
            Text("所有修改已保存")
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard draft.hasValidEndTime() else {
            message = BSLocalization.text("结束时间需晚于开始时间，请修正后保存")
            return
        }

        isSaving = true
        message = nil
        dismissKeyboard()

        do {
            try await onSave(draft)
            coverLifecycle.finalize(keeping: draft.coverImageURL, additionalDiscards: [originalCoverURL])
            didSave = true
            dismiss()
        } catch {
            message = BSLocalization.text("没有保存成功，请重试。你的修改仍保留在这里。")
            isSaving = false
        }
    }

}
