import SwiftData
import SwiftUI

/// 「我的现场」专用空态：图标瓷贴 + 品牌渐变主 CTA，
/// 比通用 BSEmptyPanel 更轻、行动指向更强。
private struct MyShowsEmptyView: View {
    let onAddShow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: BSSpacing.md) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(BSColor.brandGradientSoft)
                    .frame(width: 76, height: 76)
                    .background(BSColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(BSColor.border, lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: BSSpacing.sm) {
                    Text("我的现场为空")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                    Text("把要去和去过的现场都放进来。添加第一场后，这里会按时间保存你的所有现场。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onAddShow) {
                    Label("添加现场", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.043, green: 0.043, blue: 0.067))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(BSColor.brandGradient))
                }
                .buttonStyle(.plain)
                .padding(.top, BSSpacing.sm)
                .accessibilityLabel(BSLocalization.text("添加现场"))
            }
            .padding(.horizontal, 36)

            Spacer()
        }
        .padding(.bottom, 72)
    }
}

private struct ShowRowView: View {
    let show: Show
    let isCurrent: Bool
    let formatter: ShowDisplayFormatter
    let session: CurrentShowSession
    /// Non-nil on rows where 「设为当前」 should appear inline (upcoming / postponed,
    /// never the current or canceled row). Row tap itself opens detail.
    var setCurrentAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Covers are 3:4 posters — show the full poster instead of a square crop.
            ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 9)
                .frame(width: 46, height: 61)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(show.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)
                    if isCurrent {
                        Text("当前")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BSColor.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .layoutPriority(1)
                    }
                }

                subtitleRow

                if let venueName = show.venueName {
                    Text(venueName)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BSSpacing.sm)

            if let setCurrentAction {
                Button(action: setCurrentAction) {
                    Text("设为当前")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BSColor.Stage.accent.opacity(0.10)))
                        .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("设为当前现场"))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.textTertiary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(minHeight: BSLayout.minTouchTarget)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(
                    isCurrent
                        ? BSColor.brandGradient
                        : LinearGradient(colors: [BSColor.border], startPoint: .leading, endPoint: .trailing),
                    lineWidth: isCurrent ? 1.5 : 1
                )
        )
        .accessibilityElement(children: .contain)
    }

    /// 变更组用状态点 + 着色 subtitle 区分取消/延期；其余组保持「日期 · 状态」。
    private var subtitleRow: some View {
        HStack(spacing: 5) {
            if show.changeStatus != .scheduled {
                Circle()
                    .fill(show.changeStatus == .canceled ? BSColor.Accent.danger : BSColor.Accent.warm)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(subtitleText)
                .font(BSFont.caption)
                .foregroundColor(subtitleColor)
                .lineLimit(1)
        }
    }

    private var subtitleColor: Color {
        switch show.changeStatus {
        case .canceled:
            return BSColor.Accent.danger
        case .postponed:
            return BSColor.Accent.warm
        case .scheduled:
            return BSColor.textTertiary
        }
    }

    private var subtitleText: String {
        switch show.changeStatus {
        case .canceled:
            return BSLocalization.format("已取消 · %@", formatter.dateText(for: show))
        case .postponed:
            if show.postponedDate != nil {
                return BSLocalization.format("延期至 %@", formatter.dateText(for: show))
            }
            return BSLocalization.format("时间待定 · %@", formatter.dateText(for: show))
        case .scheduled:
            return "\(formatter.dateText(for: show)) · \(session.phase(for: show, now: Date()).statusText)"
        }
    }
}

/// 当前现场 Hero 卡：封面为 3:4 竖版海报 —— 左侧完整展示海报，
/// 背景用同图放大模糊填充，不做横向裁剪。
private struct CurrentShowListHeroCard: View {
    let show: Show
    let formatter: ShowDisplayFormatter
    let session: CurrentShowSession

    private var phase: CurrentShowTimeState {
        session.phase(for: show, now: Date())
    }

    var body: some View {
        ZStack {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 1,
                contentMode: .fill,
                enforcesAspectRatio: false,
                cornerRadius: 0
            )
            .scaleEffect(1.15)
            .blur(radius: 30)
            .overlay(Color.black.opacity(0.45))

            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(alignment: .center, spacing: 14) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    cornerRadius: BSRadius.md
                )
                .frame(width: 100)
                .shadow(color: .black.opacity(0.55), radius: 13, x: 0, y: 10)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 9, weight: .bold))
                        Text("当前现场")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.043, green: 0.043, blue: 0.067))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BSColor.brandGradient))

                    Text(show.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(2)

                    Text(metaText)
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.textSecondary)
                        .lineLimit(1)

                    countdownRow
                }

                Spacer(minLength: 0)
            }
            .padding(BSSpacing.md)
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.brandGradient, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.36), radius: 22, x: 0, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var metaText: String {
        let place = show.venueName ?? show.city ?? BSLocalization.text("现场")
        return "\(place) · \(formatter.dateText(for: show))"
    }

    private var countdownRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: BSSpacing.sm) {
            if let eyebrow = countdownContent.eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.textTertiary)
            }
            Group {
                if countdownContent.dim {
                    Text(countdownContent.value)
                        .foregroundColor(BSColor.textTertiary)
                } else {
                    Text(countdownContent.value)
                        .bsGradientText()
                }
            }
            .font(.system(size: 22, weight: .light))
        }
        .padding(.top, BSSpacing.xs)
    }

    private struct HeroCountdown {
        let eyebrow: String?
        let value: String
        var dim: Bool = false
    }

    private var countdownContent: HeroCountdown {
        switch phase.kind {
        case .before:
            return HeroCountdown(
                eyebrow: BSLocalization.text("距离开场"),
                value: "\(phase.countdownNumber)\(phase.countdownUnit)"
            )
        case .today:
            return HeroCountdown(eyebrow: nil, value: BSLocalization.text("就是今天"))
        case .dayEnded:
            return HeroCountdown(eyebrow: nil, value: BSLocalization.text("今日已落幕"), dim: true)
        case .postShow:
            return HeroCountdown(
                eyebrow: nil,
                value: "\(phase.countdownNumber)\(phase.countdownUnit)"
            )
        case .ended:
            return HeroCountdown(eyebrow: nil, value: BSLocalization.text("已结束"), dim: true)
        case .canceled:
            return HeroCountdown(eyebrow: nil, value: BSLocalization.text("记录仍保留"), dim: true)
        case .postponed:
            return HeroCountdown(eyebrow: nil, value: BSLocalization.text("倒计时已暂停"), dim: true)
        }
    }
}

// MARK: - Current Tab Secondary Show Management

enum CurrentShowLibraryFilter: String, CaseIterable, Identifiable {
    case upcoming = "即将开始"
    case ended = "已结束"
    case all = "全部"

    var id: Self { self }
}

enum CurrentShowLibraryMenuAction: String, Hashable {
    case view = "查看详情"
    case setCurrent = "设为当前展示"
    case edit = "编辑"
    case postpone = "延期"
    case editPostponedDate = "编辑新日期"
    case restoreScheduled = "恢复正常"
    case restoreCanceled = "恢复演出"
    case cancel = "取消演出"
    case delete = "删除"

    var isDestructive: Bool {
        self == .cancel || self == .delete
    }
}

enum CurrentShowLibraryMenuPolicy {
    static func actions(
        for changeStatus: ShowChangeStatus,
        timeKind: CurrentShowTimeKind,
        canSetCurrent: Bool
    ) -> [CurrentShowLibraryMenuAction] {
        switch changeStatus {
        case .postponed:
            return [.view]
                + (canSetCurrent && timeKind != .postponed ? [.setCurrent] : [])
                + [.editPostponedDate, .restoreScheduled, .cancel, .delete]
        case .canceled:
            return [.view, .restoreCanceled, .delete]
        case .scheduled:
            if timeKind == .ended {
                return [.view, .edit, .delete]
            }
            if timeKind == .postShow {
                return [.view]
                    + (canSetCurrent ? [.setCurrent] : [])
                    + [.edit, .delete]
            }

            return [.view]
                + (canSetCurrent ? [.setCurrent] : [])
                + [.edit, .postpone, .cancel, .delete]
        }
    }
}

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

    @State private var searchText = ""
    @State private var filter: CurrentShowLibraryFilter = .upcoming
    @State private var destination: CurrentShowLibraryDestination?
    @State private var deleteTarget: Show?
    @State private var postponeTarget: Show?
    @State private var postponeDate = Date()
    @State private var cancelTarget: Show?
    @State private var isShowingAdd = false
    @State private var toast: BSToastPayload?

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
                        Text("没有匹配的现场")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(displayedSections) { section in
                            if !section.shows.isEmpty {
                                managementSection(section)
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
        .navigationTitle("我的现场")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            BSChromeToolbarCloseButton { dismiss() }
            ToolbarItem(placement: .topBarTrailing) {
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
        .confirmationDialog(
            DangerConfirmation.cancelShowFromEditor.title,
            isPresented: Binding(
                get: { cancelTarget != nil },
                set: { if !$0 { cancelTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: cancelTarget
        ) { show in
            Button(DangerConfirmation.cancelShowFromEditor.confirmTitle, role: .destructive) {
                updateStatus(show, message: BSLocalization.text("已记录取消")) { show.markCanceled() }
                cancelTarget = nil
            }
        } message: { _ in
            Text(DangerConfirmation.cancelShowFromEditor.message)
        }
        .sheet(isPresented: $isShowingAdd) {
            AddShowCoordinatorSheet {
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
            ForEach(section.shows) { show in
                CurrentShowLibraryRow(
                    show: show,
                    isCurrent: selectedShowID == show.id,
                    formatter: formatter,
                    actions: menuActions(for: show),
                    onOpen: { destination = .init(show: show, startsEditing: false) },
                    onAction: { action in handle(action, for: show) }
                )
            }
        }
        .padding(.top, 23)
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
            sections = [.init(title: BSLocalization.text("即将开始"), shows: upcomingShows), .init(title: BSLocalization.text("延期与变更"), shows: changedShows)]
        case .ended:
            sections = [.init(title: BSLocalization.text("已结束"), shows: endedShows)]
        case .all:
            sections = [
                .init(title: BSLocalization.text("即将开始"), shows: upcomingShows),
                .init(title: BSLocalization.text("延期与变更"), shows: changedShows),
                .init(title: BSLocalization.text("已结束"), shows: endedShows)
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

    private var changedShows: [Show] {
        shows.filter { $0.changeStatus != .scheduled }.sorted { $0.effectiveDate < $1.effectiveDate }
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
        case .upcoming: return upcomingShows.count + changedShows.count
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
}

private struct CurrentShowLibraryRow: View {
    let show: Show
    let isCurrent: Bool
    let formatter: ShowDisplayFormatter
    let actions: [CurrentShowLibraryMenuAction]
    let onOpen: () -> Void
    let onAction: (CurrentShowLibraryMenuAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 10)
                        .frame(width: 47, height: 63)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            if isCurrent { tag(BSLocalization.text("当前展示"), color: BSColor.Stage.glowBlue) }
                            if show.changeStatus != .scheduled { tag(statusTag, color: BSColor.Accent.warm) }
                        }
                        Text(show.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Text([formatter.dateText(for: show), show.venueName ?? show.city].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11.4))
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Menu {
                ForEach(actions, id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        onAction(action)
                    } label: {
                        Label(BSLocalization.text(action.rawValue), systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.055), in: Circle())
            }
            .accessibilityLabel(BSLocalization.format("管理 %@", show.name))
            .padding(.trailing, 11)
        }
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var statusTag: String { show.changeStatus == .canceled ? BSLocalization.text("已取消") : BSLocalization.text("已延期") }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

private extension CurrentShowLibraryMenuAction {
    var icon: String {
        switch self {
        case .view: return "info.circle"
        case .setCurrent: return "music.note.house"
        case .edit: return "pencil"
        case .postpone, .editPostponedDate: return "calendar.badge.clock"
        case .restoreScheduled, .restoreCanceled: return "arrow.uturn.backward"
        case .cancel: return "xmark.circle"
        case .delete: return "trash"
        }
    }
}
