import SwiftData
import SwiftUI

private struct CurrentShowLibraryDestination: Identifiable, Hashable {
    let show: Show
    var id: String { "\(show.persistentModelID)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 从“当前”页进入的完整管理页。刻意与底部“我的现场”Tab 分离，避免改变其现有结构与状态。

struct CurrentShowLibraryManagementView: View {
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]

    @State private var searchText = ""
    @State private var destination: CurrentShowLibraryDestination?
    @State private var editingTarget: Show?
    @State private var deleteTarget: Show?
    @State private var deletingPersistentID: PersistentIdentifier?
    @State private var postponeTarget: Show?
    @State private var postponeDate = Date()
    @State private var cancelTarget: Show?
    @State private var isShowingAdd = false
    @State private var toast: BSToastPayload?
    @State private var revealedShowID: UUID?

    private let session = CurrentShowSession()

    var body: some View {
        let now = Date()
        let selectedShowID = self.selectedShowID
        let upcoming = upcomingShows(now: now).filter(matchesSearch)
        let archive = archiveGroups(now: now)
        return ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if upcoming.isEmpty && archive.isEmpty {
                        emptyStateView
                    } else {
                        if !upcoming.isEmpty {
                            sectionHeader(BSLocalization.text("即将开始"), count: upcoming.count)
                            LazyVStack(spacing: BSSpacing.sm) {
                                ForEach(upcoming, id: \.persistentModelID) { show in
                                    let actions = menuActions(for: show, selectedShowID: selectedShowID, now: now)
                                    let row = CurrentShowLibraryUpcomingRow(
                                        show: show,
                                        isCurrent: selectedShowID == show.id,
                                        phase: session.phase(for: show, now: now),
                                        actions: actions,
                                        onOpen: { destination = .init(show: show) },
                                        onAction: { action in handle(action, for: show) },
                                        onSetCurrent: actions.contains(.setCurrent) ? { selectCurrent(show) } : nil
                                    )
                                    if actions.contains(.setCurrent) {
                                        // Same gesture as 还有 N 场 on the 当前 tab.
                                        BSSwipeRevealActionRow(
                                            isRevealed: revealedShowID == show.id,
                                            actionTitle: BSLocalization.text("设为当前"),
                                            actionIcon: "pin.fill",
                                            tint: BSColor.Stage.accent,
                                            onReveal: { revealedShowID = $0 ? show.id : nil },
                                            onAction: {
                                                revealedShowID = nil
                                                selectCurrent(show)
                                            }
                                        ) { row }
                                    } else {
                                        row
                                    }
                                }
                            }
                        }
                        ForEach(archive) { group in
                            sectionHeader(String(group.year), count: group.items.count)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: BSSpacing.compact), count: 3),
                                alignment: .leading,
                                spacing: BSSpacing.md
                            ) {
                                ForEach(group.items, id: \.persistentModelID) { show in
                                    CurrentShowLibraryArchiveTile(
                                        show: show,
                                        actions: menuActions(for: show, selectedShowID: selectedShowID, now: now),
                                        onOpen: { destination = .init(show: show) },
                                        onAction: { action in handle(action, for: show) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .bsNavigationScrollEdge()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text(BSLocalization.text("搜索艺人、城市或场馆"))
        )
        .navigationTitle(BSLocalization.text("我的现场"))
       .navigationBarTitleDisplayMode(.inline)
       .toolbar(.visible, for: .navigationBar)
        .toolbar {
            BSChromeToolbarCloseButton { dismiss() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(BSColor.Stage.foreground)
                }
                .tint(BSColor.Stage.foreground)
                .accessibilityLabel(BSLocalization.text("添加现场"))
            }
        }
        .navigationDestination(item: $destination) { target in
            ShowDetailView(
                show: target.show,
                onDetailVisibilityChange: onDetailVisibilityChange
            )
        }
        .sheet(item: $editingTarget) { show in
            ShowDraftEditorView(
                title: BSLocalization.text("编辑现场"),
                draft: ShowDraft(show: show),
                saveTitle: BSLocalization.text("保存"),
                statusPillText: session.phase(for: show, now: Date()).statusText,
                isPostponed: show.changeStatus == .postponed
            ) { draft in
                let didSync = try await ShowMutationCoordinator.applyDraft(
                    draft, to: show, shows: shows, selections: selections,
                    notificationStates: notificationStates, in: modelContext, session: session
                )
                presentToast(
                    didSync ? .success : .neutral,
                    message: BSLocalization.text(didSync ? "现场信息已更新" : "信息已保存，同步暂未更新")
                )
            }
        }
        .sheet(item: $postponeTarget) { show in
            PostponeShowSheet(
                newDate: $postponeDate,
                calendar: show.timingCalendar(),
                onUndated: { applyPostponement(to: show, newDate: nil) },
                onDated: {
                    applyPostponement(
                        to: show,
                        newDate: ShowDateSelectionPolicy.normalizedDay(
                            postponeDate,
                            calendar: show.timingCalendar()
                        )
                    )
                }
            )
        }
        .alert(
            DangerConfirmation.cancelShowFromEditor.title,
            isPresented: Binding(
                get: { cancelTarget != nil },
                set: { if !$0 { cancelTarget = nil } }
            ),
            presenting: cancelTarget
        ) { show in
            Button(DangerConfirmation.cancelShowFromEditor.confirmTitle, role: .destructive) {
                updateStatus(show, message: BSLocalization.text("已记录取消")) { show.markCanceled() }
                cancelTarget = nil
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { _ in
            Text(DangerConfirmation.cancelShowFromEditor.message)
        }
        .sheet(isPresented: $isShowingAdd) {
            AddShowCoordinatorSheet { _ in
                presentToast(.success, message: BSLocalization.text("已添加现场"))
            }
        }
        .alert(BSLocalization.text("删除这场现场？"), isPresented: deleteAlertBinding, presenting: deleteTarget) { show in
            Button("删除记录", role: .destructive) { delete(show) }
            Button(BSLocalization.text("取消"), role: .cancel) { deleteTarget = nil }
        } message: { show in
            Text(BSLocalization.format("“%@”删除后无法恢复，也会从足迹统计中移除。", show.name))
        }
        .bsToastOverlay(toast, bottomPadding: 28)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(BSColor.Stage.muted)
            Spacer()
            Text(BSLocalization.format("%lld 场", count))
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .frame(height: BSSpacing.roomy)
        .padding(.top, BSSpacing.lg)
        .padding(.bottom, BSSpacing.sm)
    }

    private var visibleShows: [Show] {
        guard let deletingPersistentID else { return shows }
        return shows.filter { $0.persistentModelID != deletingPersistentID }
    }

    private var selectedShowID: UUID? {
        session.selectCurrentShow(from: visibleShows, manualSelection: selections.first)?.id
    }

    /// 未开场 / 当天的正常现场，加上所有延期现场。
    private func upcomingShows(now: Date) -> [Show] {
        visibleShows.filter { show in
            switch show.changeStatus {
            case .postponed: return true
            case .canceled: return false
            case .scheduled:
                let kind = session.phase(for: show, now: now).kind
                return kind == .before || kind == .today || kind == .dayEnded
            }
        }.map { show in
            (show: show, key: (
                date: CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar()),
                isUndated: show.changeStatus == .postponed && show.postponedDate == nil
            ))
        }
        .sorted { CurrentShowLibrarySectionPolicy.upcomingPrecedes($0.key, $1.key) }
        .map(\.show)
    }

    /// 已结束与已取消，按年份倒序。
    private func archiveGroups(now: Date) -> [CurrentShowLibrarySectionPolicy.YearGroup<Show>] {
        let archived = visibleShows.filter { show in
            switch show.changeStatus {
            case .postponed: return false
            case .canceled: return true
            case .scheduled:
                let kind = session.phase(for: show, now: now).kind
                return kind == .postShow || kind == .ended
            }
        }.filter(matchesSearch)
        return CurrentShowLibrarySectionPolicy.archiveYearGroups(
            archived,
            date: \.effectiveDate,
            year: { $0.timingCalendar().component(.year, from: $0.effectiveDate) }
        )
    }

    private func matchesSearch(_ show: Show) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = ([show.name] + show.artistNames
            + [show.city, show.venueName, show.venueAddress].compactMap { $0 })
            .joined(separator: " ")
        return ArtistNameMatching.contains(haystack, query: query)
    }

    private func menuActions(for show: Show, selectedShowID: UUID?, now: Date) -> [CurrentShowLibraryMenuAction] {
        CurrentShowLibraryMenuPolicy.actions(
            for: show.changeStatus,
            timeKind: session.phase(for: show, now: now).kind,
            canSetCurrent: show.id != selectedShowID && session.isManuallySelectable(show)
        )
    }

    private func handle(_ action: CurrentShowLibraryMenuAction, for show: Show) {
        switch action {
        case .setCurrent:
            selectCurrent(show)
        case .edit:
            editingTarget = show
        case .postpone, .editPostponedDate:
            presentPostpone(for: show)
        case .restoreScheduled:
            updateStatus(show, message: BSLocalization.text("已恢复原定日期")) { show.markScheduled() }
        case .restoreCanceled:
            updateStatus(show, message: BSLocalization.text("已撤销取消")) { show.markScheduled() }
        case .cancel:
            presentCancel(for: show)
        case .delete:
            presentDelete(show)
        }
    }

    private func presentPostpone(for show: Show) {
        postponeDate = show.postponedDate ?? show.date
        postponeTarget = show
    }

    private func applyPostponement(to show: Show, newDate: Date?) {
        postponeTarget = nil
        let message = newDate == nil ? BSLocalization.text("已记录延期，日期待定") : BSLocalization.text("延期日期已更新")
        updateStatus(show, message: message) { show.markPostponed(newDate: newDate) }
    }

    private func presentCancel(for show: Show) {
        cancelTarget = show
    }

    private func presentDelete(_ show: Show) {
        guard deletingPersistentID == nil else { return }
        deleteTarget = show
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private func selectCurrent(_ show: Show) {
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

    private func updateStatus(
        _ show: Show,
        message: String,
        mutation: @escaping () -> Void
    ) {
        Task { @MainActor in
            let result = await ShowMutationCoordinator.updateStatus(
                show: show,
                message: message,
                shows: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session,
                mutation: mutation
            )
            presentToast(result.tone, message: result.message)
        }
    }

    private func delete(_ show: Show) {
        guard deletingPersistentID == nil else { return }
        let targetPersistentID = show.persistentModelID
        let sourceShows = shows
        deleteTarget = nil
        deletingPersistentID = targetPersistentID

        Task { @MainActor in
            await Task.yield()
            do {
                let result = try await ShowDeletionCoordinator.delete(
                    show,
                    from: sourceShows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext,
                    onRecordDeleted: {
                        deletingPersistentID = targetPersistentID
                    }
                )
                deletingPersistentID = nil
                presentToast(
                    result.hasPendingMediaCleanup || !result.didSync ? .neutral : .success,
                    message: result.hasPendingMediaCleanup
                        ? (result.didSync
                            ? BSLocalization.text("现场记录已删除，部分本地副本将在下次启动继续清理")
                            : BSLocalization.text("现场记录已删除，本地副本与同步将在稍后继续"))
                        : (result.didSync ? BSLocalization.text("已删除现场") : BSLocalization.text("现场记录已删除，同步暂未更新"))
                )
            } catch {
                modelContext.rollback()
                if deletingPersistentID == targetPersistentID {
                    deletingPersistentID = nil
                }
                presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
            }
        }
    }

   private func presentToast(_ tone: BSToastTone, message: String) {
       let payload = BSToastPayload(tone: tone, message: message)
       toast = payload
       Task { @MainActor in
           try? await Task.sleep(for: .milliseconds(2200))
           if toast == payload { toast = nil }
       }
   }

    private var emptyStateView: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer(minLength: 32)
            if visibleShows.isEmpty {
                Image(systemName: "music.note.list")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(BSColor.Stage.accent)
                    .frame(width: 80, height: 80)
                    .background(Color.white.opacity(0.045), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))

                Text(BSLocalization.text("暂无现场演出"))
                    .font(BSFont.heroTitle)
                    .tracking(BSFont.titleTracking)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)

                Text(BSLocalization.text("把要去的音乐现场放进来，\n随时查看倒计时与专场信息。"))
                    .font(BSFont.body)
                    .foregroundStyle(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)

                Button {
                    isShowingAdd = true
                } label: {
                    Text(BSLocalization.text("添加现场"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.background)
                        .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                        .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, BSSpacing.sm)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(BSColor.Stage.dim)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))

                Text(BSLocalization.text("未找到相关现场"))
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSSpacing.lg)
    }
}
