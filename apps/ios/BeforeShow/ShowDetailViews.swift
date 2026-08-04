import SwiftUI
import SwiftData
import UIKit

struct PostponeShowSheet: View {
    @Binding var newDate: Date
    let onUndated: () -> Void
    let onDated: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("记录延期")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text("若新日期未定，倒计时和通知会暂停。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BSGlassPanel {
                DatePicker("新日期", selection: $newDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(BSColor.Accent.violet)
            }

            VStack(spacing: BSSpacing.sm) {
                Button("延期，日期待定", action: onUndated)
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("延期到选择的日期", action: onDated)
                    .buttonStyle(BSPrimaryButtonStyle())
                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
    }
}

private struct ConfirmedEndTimeEditorSheet: View {
    let showName: String
    let showStart: Date
    let hasConfirmedEnd: Bool
    @Binding var endTime: Date
    let onSave: () -> Void
    let onUndo: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(hasConfirmedEnd ? "修改散场时间" : "补记散场时间")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(showName)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            BSGlassPanel {
                VStack(spacing: BSSpacing.sm) {
                    DatePicker(
                        "散场日期",
                        selection: $endTime,
                        in: showStart...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "散场时间",
                        selection: $endTime,
                        in: showStart...Date(),
                        displayedComponents: .hourAndMinute
                    )
                }
                .tint(BSColor.Stage.accent)
            }

            VStack(spacing: BSSpacing.sm) {
                Button("保存散场时间", action: onSave)
                    .buttonStyle(BSPrimaryButtonStyle())
                if hasConfirmedEnd {
                    Button("撤销结束", action: onUndo)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.liveTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(BSColor.Stage.live.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                }
                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
    }
}

struct ShowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Query(sort: \Show.date) private var shows: [Show]
    let show: Show
    var startsEditing = false

    @State private var isEditing = false
    @State private var isEditingConfirmedEnd = false
    @State private var confirmedEndDraft = Date()
    @State private var toast: BSToastPayload?
    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    private var snapshot: CurrentShowSnapshot {
        session.snapshot(for: show)
    }

    private var timeState: CurrentShowTimeState { snapshot.phase }

    private var editorSubtitle: String {
        if show.changeStatus == .postponed {
            return "这里编辑原定信息；延期日期请在“现场状态”中更新。"
        }
        return "修改后会立即更新这个现场。"
    }

    private var isCurrentShow: Bool {
        session.isCurrent(show, among: shows, manualSelection: selections.first)
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    detailHero
                    managementRow
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.bottom, BSLayout.tabBarContentInset)
            }
            .scrollIndicators(.hidden)
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            ShowDraftEditorView(
                title: "编辑现场",
                subtitle: editorSubtitle,
                draft: ShowDraft(show: show),
                saveTitle: "保存",
                statusPillText: session.phase(for: show, now: Date()).statusText,
                isPostponed: show.changeStatus == .postponed,
                statusEditing: statusEditingContext
            ) { draft in
                try await apply(draft)
            }
        }
        .sheet(isPresented: $isEditingConfirmedEnd) {
            ConfirmedEndTimeEditorSheet(
                showName: show.name,
                showStart: CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: .current),
                hasConfirmedEnd: show.endedAt != nil,
                endTime: $confirmedEndDraft,
                onSave: saveConfirmedEnd,
                onUndo: undoConfirmedEnd,
                onCancel: { isEditingConfirmedEnd = false }
            )
        }
        .task {
            if startsEditing {
                isEditing = true
            }
        }
    }

    private var detailHero: some View {
        ZStack(alignment: .bottomLeading) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 1,
                contentMode: .fill,
                alignment: .top,
                enforcesAspectRatio: false,
                cornerRadius: 0
            )
            .frame(maxWidth: .infinity)
            .frame(height: 340)

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.62), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .background(.black.opacity(0.32))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BSColor.borderProminent, lineWidth: 1))
                    }
                    .accessibilityLabel("返回")

                    Spacer()
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.top, BSSpacing.md)

                Spacer()
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text(session.phase(for: show, now: Date()).statusText)
                    .font(BSFont.tag)
                    .foregroundColor(BSColor.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())

                Text(show.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)

                if let artist = show.artist {
                    Text(artist)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textSecondary)
                        .lineLimit(2)
                }

                Label(formatter.dateText(for: show), systemImage: "calendar")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                if let venueName = show.venueName {
                    Label([venueName, show.city].compactMap { $0 }.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .lineLimit(2)
                }
                if let venueAddress = show.venueAddress {
                    Label(venueAddress, systemImage: "signpost.right")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .lineLimit(2)
                }
                if let seatSection = show.seatSection {
                    Label(seatSection, systemImage: "ticket")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .lineLimit(2)
                }

                heroCountdown
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var heroCountdown: some View {
        HStack(alignment: .lastTextBaseline, spacing: BSSpacing.sm) {
            if let eyebrow = heroCountdownContent.eyebrow {
                Text(eyebrow)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            if heroCountdownContent.dim {
                Text(heroCountdownContent.value)
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(BSColor.textTertiary)
            } else {
                Text(heroCountdownContent.value)
                    .font(.system(size: 30, weight: .light))
                    .bsGradientText()
            }
        }
        .padding(.top, BSSpacing.xs)
    }

    private var heroCountdownContent: HeroCountdownContent {
        switch timeState.kind {
        case .before:
            return HeroCountdownContent(
                eyebrow: "距离开场",
                value: "\(timeState.countdownNumber)\(timeState.countdownUnit)"
            )
        case .today:
            return HeroCountdownContent(eyebrow: nil, value: "就是今天")
        case .dayEnded:
            return HeroCountdownContent(eyebrow: nil, value: "今日已落幕", dim: true)
        case .postShow:
            return HeroCountdownContent(
                eyebrow: nil,
                value: "\(timeState.countdownNumber)\(timeState.countdownUnit)"
            )
        case .ended:
            return HeroCountdownContent(eyebrow: nil, value: "已结束", dim: true)
        case .canceled:
            return HeroCountdownContent(eyebrow: nil, value: "记录仍保留", dim: true)
        case .postponed:
            return HeroCountdownContent(eyebrow: nil, value: "倒计时已暂停", dim: true)
        }
    }

    private struct HeroCountdownContent {
        let eyebrow: String?
        let value: String
        var dim: Bool = false
    }

    private var managementRow: some View {
        VStack(spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                Button {
                    isEditing = true
                } label: {
                    Label("编辑信息", systemImage: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .stroke(BSColor.borderProminent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑现场信息")

                if show.changeStatus == .canceled {
                    Label("已取消", systemImage: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.Accent.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .fill(BSColor.Accent.danger.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .stroke(BSColor.Accent.danger.opacity(0.28), lineWidth: 1)
                        )
                        .accessibilityLabel("现场已取消，不能设为当前")
                } else if isCurrentShow {
                    Label("当前现场", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.Accent.prepare)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .fill(BSColor.Accent.prepare.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md)
                                .stroke(BSColor.Accent.prepare.opacity(0.28), lineWidth: 1)
                        )
                        .accessibilityLabel("当前现场")
                } else {
                    Button {
                        selectCurrent()
                    } label: {
                        Label("设为当前现场", systemImage: "star.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: BSRadius.md)
                                    .fill(BSColor.brandGradient)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设为当前现场")
                }
            }

            if let endedAt = show.endedAt {
                Button {
                    confirmedEndDraft = endedAt
                    isEditingConfirmedEnd = true
                } label: {
                    HStack {
                        Label("修改散场时间", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text(Self.confirmedEndFormatter.string(from: endedAt))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.borderProminent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("也可以撤销结束")
            } else if timeState.kind == .postShow || timeState.kind == .ended {
                Button {
                    confirmedEndDraft = suggestedConfirmedEnd
                    isEditingConfirmedEnd = true
                } label: {
                    HStack {
                        Label("补记散场时间", systemImage: "clock.badge.checkmark")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.borderProminent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("填写真实散场日期和时间")
            }
        }
    }

    private static let confirmedEndFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private var suggestedConfirmedEnd: Date {
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current)
        return min(Date(), timeState.endBoundary ?? start)
    }

    /// 现场状态管理已并入编辑现场 sheet（状态卡 + 立即生效的操作）。
    /// 详情页只保留 hero 上的状态展示，这里注入编辑器所需的上下文。
    private var statusEditingContext: ShowStatusEditingContext {
        ShowStatusEditingContext(
            changeStatus: show.changeStatus,
            postponedDate: show.postponedDate,
            title: statusTitle,
            description: statusDescription,
            restoreTitle: restoreActionTitle,
            onRestore: {
                await updateStatus(message: restoreSuccessMessage) {
                    show.markScheduled()
                }
            },
            onPostpone: { newDate in
                if let newDate {
                    return await updateStatus(message: "延期日期已更新") {
                        show.markPostponed(newDate: newDate)
                    }
                }
                return await updateStatus(message: "已记录延期，日期待定") {
                    show.markPostponed(newDate: nil)
                }
            },
            onCancel: {
                await updateStatus(message: "已记录取消") {
                    show.markCanceled()
                }
            },
            onDelete: {
                isEditing = false
                await deleteShow()
            }
        )
    }

    private var statusTitle: String {
        switch show.changeStatus {
        case .scheduled:
            return "正常进行"
        case .postponed:
            return show.postponedDate == nil ? "已延期，日期待定" : "已延期"
        case .canceled:
            return "已取消"
        }
    }

    private var statusDescription: String {
        switch show.changeStatus {
        case .scheduled:
            return "艺人、日期、时间和场馆变化请使用上方字段直接编辑。"
        case .postponed:
            if show.postponedDate != nil {
                return "当前按新日期显示和提醒；原定日期仍保留在记录中。"
            }
            return "倒计时和通知已暂停，确定新日期后可以随时补充。"
        case .canceled:
            return "记录仍保留，但不会参与当前现场选择或发送提醒。"
        }
    }

    private var restoreActionTitle: String {
        show.changeStatus == .canceled ? "撤销取消" : "取消延期，恢复原定日期"
    }

    private var restoreSuccessMessage: String {
        show.changeStatus == .canceled ? "已撤销取消" : "已恢复原定日期"
    }

    private func selectCurrent() {
        guard show.changeStatus != .canceled else {
            presentToast(.neutral, message: "已取消现场不能设为当前")
            return
        }

        Task { @MainActor in
            ShowMutationCoordinator.updateCurrentShowFocus(
                showID: show.id,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )
            do {
                try modelContext.save()
                let didSyncNotifications = await LocalNotificationCenter.shared.applyFocusChange(
                    to: show,
                    in: modelContext
                )
                presentToast(
                    didSyncNotifications ? .success : .neutral,
                    message: didSyncNotifications ? "已设为当前现场" : "已切换现场，通知暂未更新"
                )
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: "切换失败，请重试")
            }
        }
    }

    private func saveConfirmedEnd() {
        let start = CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: .current)
        guard confirmedEndDraft >= start, confirmedEndDraft <= Date() else {
            presentToast(.failure, message: "散场时间需要在开场后、当前时间前")
            return
        }

        show.markEnded(at: confirmedEndDraft)
        do {
            try modelContext.save()
            isEditingConfirmedEnd = false
            presentToast(.success, message: "散场时间已更新")
            syncAfterConfirmedEndChange()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "散场时间没有保存，请重试")
        }
    }

    private func undoConfirmedEnd() {
        show.clearEnded()
        do {
            try modelContext.save()
            isEditingConfirmedEnd = false
            presentToast(.neutral, message: "已撤销结束，继续按现场时间计时")
            syncAfterConfirmedEndChange()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "没有撤销成功，请重试")
        }
    }

    private func syncAfterConfirmedEndChange() {
        Task { @MainActor in
            _ = await syncNotificationsToCurrentShow()
            WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }

    @MainActor
    private func apply(_ draft: ShowDraft) async throws {
        let didSyncNotifications = try await ShowMutationCoordinator.applyDraft(
            draft,
            to: show,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
        presentToast(
            didSyncNotifications ? .success : .neutral,
            message: didSyncNotifications ? "现场信息已更新" : "信息已保存，通知暂未更新"
        )
    }

    /// 应用状态变更并只返回反馈（不直接弹 toast）。
    /// 状态操作发生在编辑 sheet 内，由编辑器 `applyStatusAction` 负责展示，避免详情页与 sheet 各弹一份。
    @MainActor
    @discardableResult
    private func updateStatus(
        message: String,
        mutation: () -> Void
    ) async -> ShowStatusActionResult {
        await ShowMutationCoordinator.updateStatus(
            show: show,
            message: message,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session,
            mutation: mutation
        )
    }

    @MainActor
    private func deleteShow() async {
        do {
            let result = try await ShowDeletionCoordinator.delete(
                show,
                from: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )
            if result == .mediaCleanupPending {
                presentToast(.neutral, message: "现场记录已删除，部分本地副本将在下次启动继续清理")
            }
            dismiss()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "删除失败，请重试")
        }
    }

    @MainActor
    private func syncNotificationsToCurrentShow() async -> Bool {
        await ShowMutationCoordinator.syncNotifications(
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
    }
}
