import SwiftData
import SwiftUI

@MainActor
private func updateCurrentShowFocusModels(
    showID: UUID?,
    selections: [CurrentShowSelection],
    notificationStates: [NotificationSchedulingState],
    in modelContext: ModelContext
) {
    if let selection = selections.first {
        if let showID {
            selection.select(showID: showID)
        } else {
            selection.clearManualSelection()
        }
    } else if let showID {
        modelContext.insert(CurrentShowSelection(selectedShowID: showID))
    }

    updateNotificationFocusModel(
        showID: showID,
        notificationStates: notificationStates,
        in: modelContext
    )
}

@MainActor
private func updateNotificationFocusModel(
    showID: UUID?,
    notificationStates: [NotificationSchedulingState],
    in modelContext: ModelContext
) {
    if let notificationState = notificationStates.first {
        notificationState.focus(showID: showID)
    } else if showID != nil {
        modelContext.insert(NotificationSchedulingState(focusedShowID: showID))
    }
}

// MARK: - My Shows List View

struct MyShowsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @State private var isShowingAddShowCoordinator = false
    @State private var toast: BSToastPayload?
    @State private var detailTarget: Show?

    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    private var selectedShowID: UUID? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)?.id
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground()
                    .ignoresSafeArea()

                if shows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("我的现场")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, BSSpacing.md)
                            .padding(.top, BSSpacing.lg)

                        MyShowsEmptyView {
                            isShowingAddShowCoordinator = true
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                            HStack {
                                Text("我的现场")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(BSColor.textPrimary)
                                Spacer()
                                Button {
                                    isShowingAddShowCoordinator = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(BSColor.textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(Color.white.opacity(0.10))
                                        .clipShape(Circle())
                                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("添加现场")
                            }

                            if let currentShow = shows.first(where: { $0.id == selectedShowID }) {
                                Button {
                                    detailTarget = currentShow
                                } label: {
                                    CurrentShowListHeroCard(
                                        show: currentShow,
                                        formatter: formatter,
                                        session: session
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(currentShow.name)，当前现场，查看详情")
                            }

                            showGroup(title: "即将开始", shows: upcomingShows, allowsInlineSetCurrent: true)
                            showGroup(title: "已结束", shows: endedShows, dimmed: true)
                            showGroup(title: "变更", shows: changedShows, allowsInlineSetCurrent: true)

                            Text("点「设为当前」或左滑可切换当前现场")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, BSSpacing.md)
                        .padding(.top, BSSpacing.lg)
                        .padding(.bottom, 112)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { show in
                ShowDetailView(show: show)
            }
            .bsToastOverlay(toast, bottomPadding: 90)
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet {
                    presentToast(.success, message: "已放入当前现场")
                }
            }
        }
    }

    @ViewBuilder
    private func showGroup(
        title: String,
        shows: [Show],
        dimmed: Bool = false,
        allowsInlineSetCurrent: Bool = false
    ) -> some View {
        if !shows.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    BSSectionHeader(title: title)
                    Text("\(shows.count)")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary.opacity(0.7))
                }
                VStack(spacing: BSSpacing.sm) {
                    ForEach(shows) { show in
                        let isCurrent = show.id == selectedShowID
                        // Row tap opens detail via onTapGesture (not NavigationLink),
                        // so the inline "设为当前" button can receive its own taps.
                        // VoiceOver 通过可激活的整行按钮 + 「设为当前」自定义动作操作，
                        // 见 accessibleShowRow。
                        let setCurrentAction: (() -> Void)? =
                            allowsInlineSetCurrent && !isCurrent && show.changeStatus != .canceled
                            ? { selectCurrent(show) }
                            : nil
                        accessibleShowRow(
                            show: show,
                            isCurrent: isCurrent,
                            setCurrentAction: setCurrentAction
                        )
                        .contextMenu {
                            if !isCurrent && show.changeStatus != .canceled {
                                Button {
                                    selectCurrent(show)
                                } label: {
                                    Label("设为当前", systemImage: "music.note.house")
                                }
                            }
                            Button {
                                detailTarget = show
                            } label: {
                                Label("查看详情", systemImage: "info.circle")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !isCurrent && show.changeStatus != .canceled {
                                Button {
                                    selectCurrent(show)
                                } label: {
                                    Label("设为当前", systemImage: "music.note.house")
                                }
                                .tint(.blue)
                            }
                        }
                        .opacity(dimmed ? 0.55 : 1)
                    }
                }
            }
        }
    }

    private var upcomingShows: [Show] {
        let now = Date()
        return sortedShows.filter { show in
            let state = timeState(for: show, now: now)
            return show.changeStatus == .scheduled
                && (state.kind == .before || state.kind == .today || state.kind == .dayEnded)
        }
    }

    /// 列表行：视觉保持原样；对 VoiceOver 暴露为可激活的整行按钮（双击查看详情），
    /// 「设为当前」内联按钮合并进行元素后，以自定义动作补回，保证行始终可操作。
    @ViewBuilder
    private func accessibleShowRow(
        show: Show,
        isCurrent: Bool,
        setCurrentAction: (() -> Void)?
    ) -> some View {
        let row = ShowRowView(
            show: show,
            isCurrent: isCurrent,
            formatter: formatter,
            setCurrentAction: setCurrentAction
        )
        .contentShape(Rectangle())
        .onTapGesture {
            detailTarget = show
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showRowAccessibilityLabel(for: show, isCurrent: isCurrent))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("双击查看详情"))

        if let setCurrentAction {
            row.accessibilityAction(named: Text("设为当前")) {
                setCurrentAction()
            }
        } else {
            row
        }
    }

    private func showRowAccessibilityLabel(for show: Show, isCurrent: Bool) -> Text {
        var parts = [show.name, formatter.dateText(for: show)]
        if let venueName = show.venueName, !venueName.isEmpty {
            parts.append(venueName)
        }
        parts.append(formatter.statusText(for: show))
        if isCurrent {
            parts.append("当前现场")
        }
        return Text(parts.joined(separator: "，"))
    }

    private var endedShows: [Show] {
        let now = Date()
        return sortedShows.filter { show in
            let state = timeState(for: show, now: now)
            return show.changeStatus == .scheduled
                && (state.kind == .postShow || state.kind == .ended)
        }
    }

    private var changedShows: [Show] {
        sortedShows.filter { show in
            show.changeStatus != .scheduled
        }
    }

    private var sortedShows: [Show] {
        let currentID = selectedShowID
        let now = Date()
        return shows.sorted { first, second in
            if first.id == currentID { return true }
            if second.id == currentID { return false }
            if first.changeStatus == .canceled, second.changeStatus != .canceled { return false }
            if second.changeStatus == .canceled, first.changeStatus != .canceled { return true }

            let firstState = session.phase(for: first, now: now)
            let secondState = session.phase(for: second, now: now)
            return abs(firstState.effectiveDate.timeIntervalSince(now))
                < abs(secondState.effectiveDate.timeIntervalSince(now))
        }
    }

    private func timeState(for show: Show, now: Date = Date()) -> CurrentShowTimeState {
        session.phase(for: show, now: now)
    }

    private func selectCurrent(_ show: Show) {
        guard show.changeStatus != .canceled else {
            presentToast(.neutral, message: "已取消现场不能设为当前")
            return
        }

        Task { @MainActor in
            updateCurrentShowFocusModels(
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
}

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
                .accessibilityLabel("添加现场")
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
    /// Non-nil on rows where 「设为当前」 should appear inline (upcoming / postponed,
    /// never the current or canceled row). Row tap itself opens detail.
    var setCurrentAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Covers are 3:4 posters — show the full poster instead of a square crop.
            ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 9)
                .frame(width: 46, height: 61)
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
                .accessibilityLabel("设为当前现场")
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
            return "已取消 · \(formatter.dateText(for: show))"
        case .postponed:
            if show.postponedDate != nil {
                return "延期至 \(formatter.dateText(for: show))"
            }
            return "时间待定 · \(formatter.dateText(for: show))"
        case .scheduled:
            return "\(formatter.dateText(for: show)) · \(formatter.statusText(for: show))"
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
        let place = show.venueName ?? show.city ?? "现场"
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
                eyebrow: "距离开场",
                value: "\(phase.countdownNumber)\(phase.countdownUnit)"
            )
        case .today:
            return HeroCountdown(eyebrow: nil, value: "就是今天")
        case .dayEnded:
            return HeroCountdown(eyebrow: nil, value: "今日已落幕", dim: true)
        case .postShow:
            return HeroCountdown(
                eyebrow: nil,
                value: "\(phase.countdownNumber)\(phase.countdownUnit)"
            )
        case .ended:
            return HeroCountdown(eyebrow: nil, value: "已结束", dim: true)
        case .canceled:
            return HeroCountdown(eyebrow: nil, value: "记录仍保留", dim: true)
        case .postponed:
            return HeroCountdown(eyebrow: nil, value: "倒计时已暂停", dim: true)
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

private struct CurrentShowLibraryDestination: Identifiable, Hashable {
    let show: Show
    let startsEditing: Bool
    var id: String { "\(show.id.uuidString)-\(startsEditing)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 从“当前”页进入的完整管理页。刻意与底部“我的现场”Tab 分离，避免改变其现有结构与状态。
struct CurrentShowLibraryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]

    @State private var searchText = ""
    @State private var filter: CurrentShowLibraryFilter = .upcoming
    @State private var actionTarget: Show?
    @State private var destination: CurrentShowLibraryDestination?
    @State private var deleteTarget: Show?
    @State private var isShowingAdd = false
    @State private var toast: BSToastPayload?

    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $destination) { target in
            ShowDetailView(show: target.show, startsEditing: target.startsEditing)
        }
        .sheet(item: $actionTarget) { show in
            CurrentShowLibraryActionSheet(
                show: show,
                canSetCurrent: canSetCurrent(show),
                onView: { present(show, editing: false) },
                onSetCurrent: { selectCurrent(show) },
                onEdit: { present(show, editing: true) },
                onDelete: { presentDelete(show) },
                onCancel: { actionTarget = nil }
            )
        }
        .sheet(isPresented: $isShowingAdd) {
            AddShowCoordinatorSheet {
                presentToast(.success, message: "已添加现场")
            }
        }
        .alert("删除这场现场？", isPresented: deleteAlertBinding, presenting: deleteTarget) { show in
            Button("删除记录", role: .destructive) { delete(show) }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { show in
            Text("“\(show.name)”将从本机移除，此操作无法撤销。")
        }
        .bsToastOverlay(toast, bottomPadding: 28)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.075), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Spacer()
            Text("我的现场")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()

            Button { isShowingAdd = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.075), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加现场")
        }
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
                    Text("\(item.rawValue) \(count(for: item))")
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
                Text("\(section.shows.count) 场")
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
            }
            ForEach(section.shows) { show in
                CurrentShowLibraryRow(
                    show: show,
                    isCurrent: selectedShowID == show.id,
                    formatter: formatter,
                    onOpen: { destination = .init(show: show, startsEditing: false) },
                    onMore: { actionTarget = show }
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
            sections = [.init(title: "即将开始", shows: upcomingShows), .init(title: "延期与变更", shows: changedShows)]
        case .ended:
            sections = [.init(title: "已结束", shows: endedShows)]
        case .all:
            sections = [
                .init(title: "即将开始", shows: upcomingShows),
                .init(title: "延期与变更", shows: changedShows),
                .init(title: "已结束", shows: endedShows)
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
        return [show.name, show.artist, show.city, show.venueName, show.venueAddress]
            .compactMap { $0 }
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
    }

    private func count(for filter: CurrentShowLibraryFilter) -> Int {
        switch filter {
        case .upcoming: return upcomingShows.count + changedShows.count
        case .ended: return endedShows.count
        case .all: return shows.count
        }
    }

    private func canSetCurrent(_ show: Show) -> Bool {
        show.id != selectedShowID && show.changeStatus != .canceled && !endedShows.contains(where: { $0.id == show.id })
    }

    private func present(_ show: Show, editing: Bool) {
        actionTarget = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            destination = .init(show: show, startsEditing: editing)
        }
    }

    private func presentDelete(_ show: Show) {
        actionTarget = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            deleteTarget = show
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private func selectCurrent(_ show: Show) {
        actionTarget = nil
        Task { @MainActor in
            updateCurrentShowFocusModels(showID: show.id, selections: selections, notificationStates: notificationStates, in: modelContext)
            do {
                try modelContext.save()
                _ = await LocalNotificationCenter.shared.applyFocusChange(to: show, in: modelContext)
                WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
                presentToast(.success, message: "已设为当前现场")
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: "切换失败，请重试")
            }
        }
    }

    private func delete(_ show: Show) {
        deleteTarget = nil
        Task { @MainActor in
            let cover = show.coverImageURL
            if selections.first?.selectedShowID == show.id { selections.first?.clearManualSelection() }
            let remaining = shows.filter { $0.id != show.id }
            modelContext.delete(show)
            let next = session.selectCurrentShow(from: remaining, manualSelection: selections.first)
            updateNotificationFocusModel(showID: next?.id, notificationStates: notificationStates, in: modelContext)
            do {
                try modelContext.save()
                if let cover, !remaining.contains(where: { $0.coverImageURL == cover }) {
                    ShowCoverLocalImageStore.removeManagedLocalImage(at: cover)
                }
                _ = await LocalNotificationCenter.shared.applyFocusChange(to: next, in: modelContext)
                WidgetDataSync.sync(shows: remaining, manualSelection: selections.first)
                presentToast(.success, message: "已删除现场")
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: "删除失败，请重试")
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
    let onOpen: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 10)
                        .frame(width: 47, height: 63)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            if isCurrent { tag("当前展示", color: BSColor.Stage.glowBlue) }
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
            }
            .buttonStyle(.plain)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("管理 \(show.name)")
        }
        .padding(11)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var statusTag: String { show.changeStatus == .canceled ? "已取消" : "已延期" }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

private struct CurrentShowLibraryActionSheet: View {
    let show: Show
    let canSetCurrent: Bool
    let onView: () -> Void
    let onSetCurrent: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
            Text(show.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                action("查看详情", icon: "info.circle", action: onView)
                if canSetCurrent { action("设为当前展示", icon: "music.note.house", action: onSetCurrent) }
                action("编辑现场", icon: "pencil", action: onEdit)
                action("删除记录", icon: "trash", color: BSColor.Stage.liveTitle, action: onDelete)
            }
            Button("取消", action: onCancel).buttonStyle(BSSecondaryButtonStyle())
        }
    }

    private func action(_ title: String, icon: String, color: Color = BSColor.Stage.foreground, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 47)
        }
        .buttonStyle(.plain)
    }
}

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
                statusPillText: formatter.statusText(for: show),
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
                Text(formatter.statusText(for: show))
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
            updateCurrentShowFocusModels(
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
        do {
            try show.apply(draft)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        let didSyncNotifications = await syncNotificationsToCurrentShow()
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
        mutation()
        if show.changeStatus == .canceled,
           selections.first?.selectedShowID == show.id {
            selections.first?.clearManualSelection()
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return ShowStatusActionResult(tone: .failure, message: "状态没有保存，请重试")
        }

        let didSyncNotifications = await syncNotificationsToCurrentShow()
        let presentedMessage = didSyncNotifications ? message : "\(message)，通知暂未更新"
        return ShowStatusActionResult(
            tone: didSyncNotifications ? .success : .neutral,
            message: presentedMessage
        )
    }

    @MainActor
    private func deleteShow() async {
        let coverImageURL = show.coverImageURL
        if selections.first?.selectedShowID == show.id {
            selections.first?.clearManualSelection()
        }

        let remainingShows = shows.filter { $0.id != show.id }
        modelContext.delete(show)
        let nextCurrentShow = session.selectCurrentShow(
            from: remainingShows,
            manualSelection: selections.first
        )
        updateNotificationFocusModel(
            showID: nextCurrentShow?.id,
            notificationStates: notificationStates,
            in: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "删除失败，请重试")
            return
        }

        if let coverImageURL {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: coverImageURL)
        }
        _ = await LocalNotificationCenter.shared.applyFocusChange(
            to: nextCurrentShow,
            in: modelContext
        )
        dismiss()
    }

    @MainActor
    private func syncNotificationsToCurrentShow() async -> Bool {
        let currentShow = session.selectCurrentShow(
            from: shows,
            manualSelection: selections.first
        )
        updateNotificationFocusModel(
            showID: currentShow?.id,
            notificationStates: notificationStates,
            in: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }

        return await LocalNotificationCenter.shared.applyFocusChange(
            to: currentShow,
            in: modelContext
        )
    }
}
