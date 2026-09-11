import SwiftData
import SwiftUI

private struct CurrentShowLibraryDestination: Identifiable, Hashable {
    let show: Show
    let startsEditing: Bool
    var id: String { "\(show.id.uuidString)-\(startsEditing)" }

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
    @AppStorage(CurrentShowLibraryLayout.storageKey) private var layoutRawValue = CurrentShowLibraryLayout.list.rawValue

    @State private var searchText = ""
    @State private var filter: CurrentShowLibraryFilter = .all
    @State private var destination: CurrentShowLibraryDestination?
    @State private var deleteTarget: Show?
    @State private var postponeTarget: Show?
    @State private var postponeDate = Date()
    @State private var cancelTarget: Show?
    @State private var isShowingAdd = false
    @State private var toast: BSToastPayload?
    /// 冷启动时已有持久化数据必须直接可见；之后筛选 / 搜索不重播入场动画。
    @State private var rowsAppeared = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                   searchField.padding(.top, 18)
                   filterBar.padding(.top, 12)

                   if displayedSections.allSatisfy({ $0.shows.isEmpty }) {
                        emptyStateView
                   } else {
                       ForEach(displayedSections) { section in
                           if !section.shows.isEmpty {
                                managementSection(section)
                                    .bsScrollReveal(
                                        reduceMotion: reduceMotion,
                                        delay: Double(min(displayedSections.firstIndex(where: { $0.id == section.id }) ?? 0, 6)) * 0.04
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
           .scrollIndicators(.hidden)
           .scrollDismissesKeyboard(.interactively)
           .bsNavigationScrollEdge()
       }
        .navigationTitle(BSLocalization.text("我的现场"))
       .navigationBarTitleDisplayMode(.inline)
       .toolbar(.visible, for: .navigationBar)
        .toolbar {
            BSChromeToolbarCloseButton { dismiss() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: toggleLayout) {
                    Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(
                    BSLocalization.text(layout == .list ? "切换为封面展示" : "切换为列表展示")
                )

                Button {
                    isShowingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(BSLocalization.text("添加现场"))
            }
        }
        .navigationDestination(item: $destination) { target in
            ShowDetailView(
                show: target.show,
                startsEditing: target.startsEditing,
                onDetailVisibilityChange: onDetailVisibilityChange
            )
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

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(BSColor.Stage.dim)
            TextField("搜索艺人、城市或场馆", text: $searchText)
                .font(.system(size: 13))
                .foregroundColor(BSColor.Stage.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .frame(height: 47)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(CurrentShowLibraryFilter.allCases) { item in
                Button { filter = item } label: {
                    Text("\(BSLocalization.text(item.rawValue)) \(count(for: item))")
                        .font(.system(size: 12, weight: filter == item ? .semibold : .regular))
                        .foregroundColor(filter == item ? BSColor.Stage.foreground : BSColor.Stage.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(filter == item ? Color.white.opacity(0.10) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func managementSection(_ section: LibrarySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .foregroundColor(BSColor.Stage.muted)
                Spacer()
                Text(BSLocalization.format("%lld 场", section.shows.count))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
            }
            if layout == .covers {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: BSSpacing.compact),
                        count: 3
                    ),
                    alignment: .leading,
                    spacing: BSSpacing.md
                ) {
                    ForEach(Array(section.shows.enumerated()), id: \.element.id) { index, show in
                        CurrentShowLibraryCoverCard(
                            show: show,
                            isCurrent: selectedShowID == show.id,
                            actions: menuActions(for: show),
                            onOpen: { destination = .init(show: show, startsEditing: false) },
                            onAction: { action in handle(action, for: show) }
                        )
                        .modifier(LibraryRowEntrance(index: index, appeared: rowsAppeared, reduceMotion: reduceMotion))
                    }
                }
            } else {
                ForEach(Array(section.shows.enumerated()), id: \.element.id) { index, show in
                    CurrentShowLibraryRow(
                        show: show,
                        isCurrent: selectedShowID == show.id,
                        formatter: formatter,
                        actions: menuActions(for: show),
                        onOpen: { destination = .init(show: show, startsEditing: false) },
                        onAction: { action in handle(action, for: show) }
                    )
                    .modifier(LibraryRowEntrance(index: index, appeared: rowsAppeared, reduceMotion: reduceMotion))
                }
            }
        }
        .padding(.top, 23)
    }

    private var layout: CurrentShowLibraryLayout {
        CurrentShowLibraryLayout(rawValue: layoutRawValue) ?? .list
    }

    private func toggleLayout() {
        layoutRawValue = layout == .list
            ? CurrentShowLibraryLayout.covers.rawValue
            : CurrentShowLibraryLayout.list.rawValue
    }

    private struct LibrarySection: Identifiable {
        let title: String
        let shows: [Show]
        var id: String { title }
    }

    private var displayedSections: [LibrarySection] {
        let sections: [LibrarySection]
        switch filter {
        case .upcoming:
            sections = [
                .init(title: BSLocalization.text("即将开始"), shows: upcomingShows),
                .init(title: BSLocalization.text("已延期"), shows: postponedShows)
            ]
        case .ended:
            sections = [
                .init(title: BSLocalization.text("已结束"), shows: endedShows)
            ]
        case .all:
            sections = [
                .init(title: BSLocalization.text("即将开始"), shows: upcomingShows),
                .init(title: BSLocalization.text("已延期"), shows: postponedShows),
                .init(title: BSLocalization.text("已结束"), shows: endedShows),
                .init(title: BSLocalization.text("已取消"), shows: canceledShows)
            ]
        }
        return sections.map { .init(title: $0.title, shows: $0.shows.filter(matchesSearch)) }
    }

    private var selectedShowID: UUID? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)?.id
    }

    private var upcomingShows: [Show] {
        shows.filter { show in
            guard show.changeStatus == .scheduled else { return false }
            let kind = session.phase(for: show, now: Date()).kind
            return kind == .before || kind == .today || kind == .dayEnded
        }.sorted { $0.effectiveDate < $1.effectiveDate }
    }

    private var endedShows: [Show] {
        shows.filter { show in
            guard show.changeStatus == .scheduled else { return false }
            let kind = session.phase(for: show, now: Date()).kind
            return kind == .postShow || kind == .ended
        }.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    private var postponedShows: [Show] {
        shows.filter { $0.changeStatus == .postponed }.sorted { $0.effectiveDate < $1.effectiveDate }
    }

    private var canceledShows: [Show] {
        shows.filter { $0.changeStatus == .canceled }.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    private func matchesSearch(_ show: Show) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = ([show.name] + show.artistNames
            + [show.city, show.venueName, show.venueAddress].compactMap { $0 })
            .joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private func count(for filter: CurrentShowLibraryFilter) -> Int {
        switch filter {
        case .upcoming: return upcomingShows.count + postponedShows.count
        case .ended: return endedShows.count
        case .all: return shows.count
        }
    }

    private func menuActions(for show: Show) -> [CurrentShowLibraryMenuAction] {
        CurrentShowLibraryMenuPolicy.actions(
            for: show.changeStatus,
            timeKind: session.phase(for: show, now: Date()).kind,
            canSetCurrent: show.id != selectedShowID && session.isManuallySelectable(show)
        )
    }

    private func handle(_ action: CurrentShowLibraryMenuAction, for show: Show) {
        switch action {
        case .view:
            present(show, editing: false)
        case .setCurrent:
            selectCurrent(show)
        case .edit:
            present(show, editing: true)
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

    private func present(_ show: Show, editing: Bool) {
        destination = .init(show: show, startsEditing: editing)
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
        deleteTarget = show
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private func selectCurrent(_ show: Show) {
        guard session.isManuallySelectable(show) else {
            presentToast(.neutral, message: BSLocalization.text("当前状态不能设为当前现场"))
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
        deleteTarget = nil
        Task { @MainActor in
            do {
                let result = try await ShowDeletionCoordinator.delete(
                    show,
                    from: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext
                )
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
                presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
            }
        }
    }

   private func presentToast(_ tone: BSToastTone, message: String) {
       let payload = BSToastPayload(tone: tone, message: message)
       toast = payload
       Task { @MainActor in
           try? await Task.sleep(nanoseconds: 2_200_000_000)
           if toast == payload { toast = nil }
       }
   }

    private var emptyStateView: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer(minLength: 32)
            if shows.isEmpty {
                Image(systemName: "music.note.list")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 80, height: 80)
                    .background(Color.white.opacity(0.045), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))

                Text(BSLocalization.text("暂无现场演出"))
                    .font(BSFont.heroTitle)
                    .tracking(BSFont.titleTracking)
                    .foregroundColor(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)

                Text(BSLocalization.text("把要去的音乐现场放进来，\n随时查看倒计时与专场信息。"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)

                Button {
                    isShowingAdd = true
                } label: {
                    Text(BSLocalization.text("添加现场"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(BSColor.Stage.background)
                        .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                        .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, BSSpacing.sm)
            } else if isSearching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))

                Text(BSLocalization.text("未找到相关现场"))
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)

                Text(BSLocalization.text("尝试更换搜索词或切换筛选分类"))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
            } else {
                Image(systemName: filterEmptyIcon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))

                Text(filterEmptyTitle)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)

                Text(filterEmptySubtitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSSpacing.lg)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filterEmptyIcon: String {
        switch filter {
        case .upcoming: return "calendar.badge.clock"
        case .ended: return "clock.arrow.circlepath"
        case .all: return "music.note.list"
        }
    }

    private var filterEmptyTitle: String {
        switch filter {
        case .upcoming: return BSLocalization.text("暂无即将开始的现场")
        case .ended: return BSLocalization.text("暂无已结束的现场")
        case .all: return BSLocalization.text("暂无现场演出")
        }
    }

    private var filterEmptySubtitle: String {
        switch filter {
        case .upcoming: return BSLocalization.text("添加新的演出，或在全部记录中查看历史")
        case .ended: return BSLocalization.text("演出结束后会自动归档到这里")
        case .all: return BSLocalization.text("尝试更换筛选分类")
        }
    }
}
