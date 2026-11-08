import SwiftUI
import SwiftData
import UIKit

struct ShowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var showAssets: [ShowAsset]
    @Query private var memoryFragments: [MemoryFragment]
    let show: Show
    var startsEditing = false
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @State private var presentedSheet: ShowDetailPresentedSheet?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingCancelConfirmation = false
    @State private var confirmedEndDraft = Date()
    @State private var postponeDraft = Date()
    @State private var isShowingCoverPreview = false
    @Namespace private var coverTransition
    @State private var isDeleting = false
    @State private var toast: BSToastPayload?
    @State private var memoryCreate: MemoryCreateSourceOption?
    /// Moves on each minute so the stage turns LIVE, and later ends, while the page stays open.
    @State private var now = Date()
    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    init(
        show: Show,
        startsEditing: Bool = false,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.show = show
        self.startsEditing = startsEditing
        self.onDetailVisibilityChange = onDetailVisibilityChange
        let showID = show.id
        _showAssets = Query(
            filter: #Predicate<ShowAsset> { asset in
                asset.showID == showID
            }
        )
        _memoryFragments = Query(
            filter: #Predicate<MemoryFragment> { fragment in
                fragment.showID == showID
            }
        )
    }

    private var snapshot: CurrentShowSnapshot {
        session.snapshot(for: show, now: now)
    }

    private var timeState: CurrentShowTimeState { snapshot.phase }

    private var isCurrentShow: Bool {
        session.isCurrent(show, among: shows, manualSelection: selections.first)
    }

    var body: some View {
        GeometryReader { proxy in
            content(topInset: proxy.safeAreaInsets.top)
        }
    }

    @ViewBuilder
    private func content(topInset: CGFloat) -> some View {
        ZStack {
            BSColor.Stage.background
                .ignoresSafeArea()

            if isDeleting {
                ProgressView()
                    .tint(BSColor.Stage.foreground)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                        ShowDetailStageHero(
                            show: show,
                            mood: stageMood,
                            startTime: timeState.effectiveStartTime,
                            endTime: show.endedAt ?? timeState.effectiveEndTime,
                            reunions: ShowDetailStagePolicy.reunions(for: show, among: shows, now: Date())
                                .map { .init(name: $0.name, nth: $0.nth) },
                            coverTransition: coverTransition,
                            onOpenCover: { isShowingCoverPreview = true },
                            topExtension: topInset
                        )
                        ShowDetailKit(
                            isAfterShow: stageMood == .ended,
                            assets: ShowAssetManagementPolicy.entries(for: show, assets: showAssets),
                            assetFileURL: assetFileURL,
                            companionSubtitle: companionPresentationSubtitle,
                            hasCompanion: show.hasCompanions,
                            onAsset: { presentedSheet = .asset($0) },
                            onCompanion: { presentedSheet = .companion }
                        )
                        .padding(.top, BSSpacing.sm)
                        MemoryContactSheet(
                            fragments: memoryFragments.sorted { $0.createdAt < $1.createdAt },
                            currentPhase: MemoryFragmentPhase.resolved(at: Date(), timing: show.timingFields),
                            onOpen: { _ in openMemory(creating: nil) },
                            onOpenList: { openMemory(creating: nil) },
                            onCreate: { openMemory(creating: $0) }
                        )
                        BSProgrammeInfo(rows: programmeRows)
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
                    .padding(.bottom, BSSpacing.xl)
                }
                .bsStageNavigationChrome()
            }
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        // The stage carries the page; the bar keeps only its buttons. The title still names the page for Back.
        .navigationTitle(BSLocalization.text("现场详情"))
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !isDeleting {
                ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(BSLocalization.text("编辑"), systemImage: "square.and.pencil") {
                        presentedSheet = .editor
                    }
                    if isCurrentShow {
                        Button {} label: {
                            Label(BSLocalization.text("当前展示中"), systemImage: "checkmark.circle")
                        }
                        .disabled(true)
                    } else if session.isManuallySelectable(show) {
                        Button(BSLocalization.text("设为当前现场"), systemImage: "music.note.house", action: selectCurrent)
                    }
                    Menu {
                        eventStatusMenuActions
                    } label: {
                        Label(statusTitle, systemImage: eventStatusIcon)
                    }
                    Button(BSLocalization.text("删除"), systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                    .accessibilityLabel(BSLocalization.text("更多操作"))
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editor:
                ShowDraftEditorView(
                    title: BSLocalization.text("编辑现场"),
                    draft: ShowDraft(show: show),
                    saveTitle: BSLocalization.text("保存"),
                    statusPillText: session.phase(for: show, now: Date()).statusText,
                    isPostponed: show.changeStatus == .postponed
                ) { draft in
                    try await apply(draft)
                }
            case .confirmedEnd:
                ConfirmedEndTimeEditorSheet(
                    showName: show.name,
                    showStart: CurrentShowTimeState.minimumConfirmableEnd(
                        for: show,
                        calendar: show.timingCalendar()
                    ),
                    calendar: show.endTimingCalendar(),
                    hasConfirmedEnd: show.endedAt != nil,
                    endTime: $confirmedEndDraft,
                    onSave: saveConfirmedEnd,
                    onUndo: undoConfirmedEnd
                )
            case .asset(let kind):
                ShowAssetSheet(
                    showID: show.id,
                    showName: show.name,
                    kind: kind,
                    onDetailVisibilityChange: onDetailVisibilityChange,
                    keepsParentDetailHidden: true
                )
            case .memory:
                MemoryFragmentsSheet(show: show, pendingCreate: memoryCreate)
            case .companion:
                CompanionEditorSheet(show: show)
            case .postpone:
                PostponeShowSheet(
                    newDate: $postponeDraft,
                    calendar: show.timingCalendar(),
                    onUndated: {
                        presentedSheet = nil
                        applyStatus(message: BSLocalization.text("已记录延期，日期待定")) {
                            show.markPostponed(newDate: nil)
                        }
                    },
                    onDated: {
                        let newDate = ShowDateSelectionPolicy.normalizedDay(
                            postponeDraft,
                            calendar: show.timingCalendar()
                        )
                        presentedSheet = nil
                        applyStatus(message: BSLocalization.text("延期日期已更新")) {
                            show.markPostponed(newDate: newDate)
                        }
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isShowingCoverPreview) {
            ShowCoverFullscreenPreview(urlString: show.coverImageURL)
                .bsNavigationZoom(sourceID: "cover", in: coverTransition)
        }
        .alert(
            DangerConfirmation.deleteShow.title,
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button(DangerConfirmation.deleteShow.confirmTitle, role: .destructive) {
                beginDelete()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.deleteShow.message)
        }
        .alert(
            DangerConfirmation.cancelShow.title,
            isPresented: $isShowingCancelConfirmation
        ) {
            Button(DangerConfirmation.cancelShow.confirmTitle, role: .destructive) {
                applyStatus(message: BSLocalization.text("已记录取消")) { show.markCanceled() }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.cancelShow.message)
        }
        .task {
            if startsEditing {
                presentedSheet = .editor
            }
        }
        .onAppear { onDetailVisibilityChange(true) }
        .onDisappear { onDetailVisibilityChange(false) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)))
                now = Date()
            }
        }
    }

    private var stageMood: ShowStageMood {
        ShowDetailStagePolicy.mood(
            changeStatus: show.changeStatus,
            postponedDate: show.postponedDate,
            phase: HomeShowPhase(timeState: timeState),
            dayDistance: timeState.dayDistance,
            isDayEnded: timeState.kind == .dayEnded
        )
    }

    private func openMemory(creating option: MemoryCreateSourceOption?) {
        memoryCreate = option
        presentedSheet = .memory
    }

    private func assetFileURL(_ kind: ShowAssetKind) -> URL? {
        guard let asset = showAssets.first(where: { $0.kind == kind }),
              let location = try? ShowAssetMediaLocation.applicationSupport() else { return nil }
        return location.rootDirectory.appendingPathComponent(asset.relativePath)
    }

    /// The programme rows; the end time becomes an action once the show is over.
    private var programmeRows: [BSProgrammeInfo.Row] {
        let endCalendar = show.endTimingCalendar()
        var rows = [BSProgrammeInfo.Row(label: "WHEN", value: formatter.dateText(for: show))]
        if let endedAt = show.endedAt {
            rows.append(.init(
                label: "ENDS",
                value: BSLocalization.format("已于 %@ 结束", formattedDate(endedAt, format: BSLocalization.text("M月d日 HH:mm"), calendar: endCalendar)),
                actionTitle: BSLocalization.text("修改"),
                action: {
                    confirmedEndDraft = endedAt
                    presentedSheet = .confirmedEnd
                }
            ))
        } else if timeState.kind == .postShow || timeState.kind == .ended {
            rows.append(.init(
                label: "ENDS",
                value: BSLocalization.text("尚未确认散场时间"),
                detail: BSLocalization.text("按实际填写，时长更准"),
                actionTitle: BSLocalization.text("补记"),
                action: {
                    confirmedEndDraft = suggestedConfirmedEnd
                    presentedSheet = .confirmedEnd
                }
            ))
        } else if let endTime = timeState.effectiveEndTime {
            rows.append(.init(label: "ENDS", value: BSLocalization.format("预计 %@ 结束", formattedDate(endTime, format: "HH:mm", calendar: endCalendar))))
        }
        rows.append(.init(label: "VENUE", value: show.venueName ?? BSLocalization.text("未填写场馆")))
        if let address = show.venueAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            rows.append(.init(label: "ADDR", value: address))
        }
        rows.append(.init(label: "CITY", value: show.city ?? BSLocalization.text("未填写城市")))
        if show.artists.isEmpty {
            rows.append(.init(label: "LINEUP", value: BSLocalization.text("未填写艺人")))
        }
        return rows
    }

    private var companionPresentationSubtitle: String {
        CompanionQuickActionPresentation(companionNames: show.companionNames).displayTitle
    }

    @ViewBuilder
    private var eventStatusMenuActions: some View {
        switch show.changeStatus {
        case .scheduled:
            Button(BSLocalization.text("延期"), systemImage: "calendar.badge.clock") {
                beginPostpone()
            }
            Button(BSLocalization.text("记录取消"), systemImage: "xmark.circle", role: .destructive) {
                isShowingCancelConfirmation = true
            }
        case .postponed:
            Button(BSLocalization.text("修改延期"), systemImage: "calendar.badge.clock") {
                beginPostpone()
            }
            Button(BSLocalization.text("记录取消"), systemImage: "xmark.circle", role: .destructive) {
                isShowingCancelConfirmation = true
            }
            Button(restoreActionTitle, systemImage: "arrow.clockwise") {
                applyStatus(message: restoreSuccessMessage) { show.markScheduled() }
            }
        case .canceled:
            Button(restoreActionTitle, systemImage: "arrow.clockwise") {
                applyStatus(message: restoreSuccessMessage) { show.markScheduled() }
            }
        }
    }

    private var eventStatusIcon: String {
        switch show.changeStatus {
        case .scheduled: return "checkmark"
        case .postponed: return show.postponedDate == nil ? "ellipsis" : "arrow.clockwise"
        case .canceled: return "xmark"
        }
    }

    private func formattedDate(_ date: Date, format: String, calendar: Calendar? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = format
        formatter.timeZone = (calendar ?? show.timingCalendar()).timeZone
        return formatter.string(from: date)
    }

    private var suggestedConfirmedEnd: Date {
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar())
        return min(Date(), timeState.endBoundary ?? start)
    }

    private var statusTitle: String {
        switch show.changeStatus {
        case .scheduled:
            return BSLocalization.text("正常进行中")
        case .postponed:
            return show.postponedDate == nil ? BSLocalization.text("时间待定") : BSLocalization.text("已改期")
        case .canceled:
            return BSLocalization.text("演出已取消")
        }
    }

    private var restoreActionTitle: String {
        BSLocalization.text("恢复正常状态")
    }

    private var restoreSuccessMessage: String {
        show.changeStatus == .canceled ? BSLocalization.text("已撤销取消") : BSLocalization.text("已恢复原定日期")
    }

    private func beginPostpone() {
        postponeDraft = show.postponedDate
            ?? show.timingCalendar().date(byAdding: .day, value: 7, to: show.effectiveDate)
            ?? show.effectiveDate
        presentedSheet = .postpone
    }

    private func applyStatus(message: String, mutation: @escaping () -> Void) {
        Task { @MainActor in
            let result = await updateStatus(message: message, mutation: mutation)
            presentToast(result.tone, message: result.message)
        }
    }

    private func selectCurrent() {
        guard session.isManuallySelectable(show) else {
            presentToast(.neutral, message: BSLocalization.text("这场不能设为当前现场"))
            return
        }

        Task { @MainActor in
            do {
                let didSync = try await ShowMutationCoordinator.selectCurrentShow(
                    showID: show.id,
                    shows: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext,
                    session: session
                )
                presentToast(
                    didSync ? .success : .neutral,
                    message: didSync ? BSLocalization.text("已设为当前现场") : BSLocalization.text("已切换现场，同步暂未更新")
                )
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: BSLocalization.text("切换失败，请重试"))
            }
        }
    }

    private func saveConfirmedEnd() {
        guard CurrentShowEndPolicy.isValidConfirmedEnd(confirmedEndDraft, for: show) else {
            presentToast(.failure, message: BSLocalization.text("散场时间需要在开场后、当前时间前"))
            return
        }

        Task { @MainActor in
            do {
                let didSync = try await ShowMutationCoordinator.commitCurrentShowChange(
                    shows: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext,
                    session: session
                ) {
                    show.markEnded(at: confirmedEndDraft)
                }
                presentedSheet = nil
                presentToast(
                    didSync ? .success : .neutral,
                    message: didSync ? BSLocalization.text("散场时间已更新") : BSLocalization.text("散场时间已保存，同步暂未更新")
                )
            } catch {
                presentToast(.failure, message: BSLocalization.text("散场时间没有保存，请重试"))
            }
        }
    }

    private func undoConfirmedEnd() {
        Task { @MainActor in
            do {
                let didSync = try await ShowMutationCoordinator.commitCurrentShowChange(
                    shows: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext,
                    session: session
                ) {
                    show.clearEnded()
                }
                presentedSheet = nil
                presentToast(
                    .neutral,
                    message: didSync
                        ? BSLocalization.text("已撤销结束，继续按现场时间计时")
                        : BSLocalization.text("已撤销结束，同步暂未更新")
                )
            } catch {
                presentToast(.failure, message: BSLocalization.text("没有撤销成功，请重试"))
            }
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            if toast == payload {
                toast = nil
            }
        }
    }

    @MainActor
    private func apply(_ draft: ShowDraft) async throws {
        let didSync = try await ShowMutationCoordinator.applyDraft(
            draft,
            to: show,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
        presentToast(
            didSync ? .success : .neutral,
            message: didSync ? BSLocalization.text("现场信息已更新") : BSLocalization.text("信息已保存，同步暂未更新")
        )
    }

    /// 状态操作在详情页独立生效，并返回统一的反馈语气与文案。
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

    private func beginDelete() {
        guard !isDeleting else { return }
        presentedSheet = nil
        isShowingCoverPreview = false
        isDeleting = true
        Task { @MainActor in
            await Task.yield()
            await deleteShow()
        }
    }

    @MainActor
    private func deleteShow() async {
        do {
            let result = try await ShowDeletionCoordinator.delete(
                show,
                from: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                onRecordDeleted: {
                    isDeleting = true
                }
            )
            if result.hasPendingMediaCleanup {
                presentToast(
                    .neutral,
                    message: result.didSync
                        ? BSLocalization.text("现场记录已删除，部分本地副本将在下次启动继续清理")
                        : BSLocalization.text("现场记录已删除，本地副本与同步将在稍后继续")
                )
            } else if !result.didSync {
                presentToast(.neutral, message: BSLocalization.text("现场记录已删除，同步暂未更新"))
            }
            dismiss()
        } catch {
            modelContext.rollback()
            isDeleting = false
            presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
        }
    }

}
