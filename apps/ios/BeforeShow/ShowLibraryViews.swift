import SwiftData
import SwiftUI

enum ShowDeletionResult: Equatable {
    case complete
    case mediaCleanupPending
}

@MainActor
enum ShowDeletionCoordinator {
    static func delete(
        _ show: Show,
        from shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext
    ) async throws -> ShowDeletionResult {
        await ShowAssetMediaStore.shared.acquireCommitGate()
        do {
            let coverImageURL = show.coverImageURL
            if selections.first?.selectedShowID == show.id {
                selections.first?.clearManualSelection()
            }

            let showID = show.id
            let dynamicCoverPath = show.dynamicCover?.relativePath
            let remainingShows = shows.filter { $0.id != showID }
            let fragments = try modelContext.fetch(
                FetchDescriptor<MemoryFragment>(predicate: #Predicate { $0.showID == showID })
            )
            for fragment in fragments {
                modelContext.delete(fragment)
            }
            let assets = try modelContext.fetch(
                FetchDescriptor<ShowAsset>(predicate: #Predicate { $0.showID == showID })
            )
            for asset in assets {
                modelContext.delete(asset)
            }
            modelContext.delete(show)
            let nextCurrentShow = CurrentShowSession().selectCurrentShow(
                from: remainingShows,
                manualSelection: selections.first
            )
            ShowMutationCoordinator.updateNotificationFocus(
                showID: nextCurrentShow?.id,
                notificationStates: notificationStates,
                in: modelContext
            )

            try modelContext.save()
            DynamicCoverFaceStore.clear(showID: showID)
            try? await MemoryFragmentMediaStore.shared.deleteShow(showID)
            var cleanupPending = false
            if let dynamicCoverPath {
                do {
                    try await DynamicCoverMediaStore.shared.deleteShow(showID)
                } catch {
                    ShowAssetCleanupRetry.markDynamicCoverCleanupPending(
                        showID: showID,
                        relativePath: dynamicCoverPath
                    )
                    cleanupPending = true
                }
            }
            ShowAssetCleanupRetry.markShowCleanupPending(showID)
            do {
                try await ShowAssetMediaStore.shared.deleteShow(showID)
            } catch {
                cleanupPending = true
            }
            if cleanupPending {
                ShowAssetCleanupRetry.markShowCleanupPending(showID)
            } else {
                ShowAssetCleanupRetry.clearShowCleanupPending(showID)
            }

            if let coverImageURL,
               !remainingShows.contains(where: { $0.coverImageURL == coverImageURL }) {
                ShowCoverLocalImageStore.removeManagedLocalImage(at: coverImageURL)
            }
            _ = await LocalNotificationCenter.shared.applyFocusChange(
                to: nextCurrentShow,
                in: modelContext
            )
            WidgetDataSync.sync(shows: remainingShows, manualSelection: selections.first)
            await ShowAssetMediaStore.shared.releaseCommitGate()
            return cleanupPending ? .mediaCleanupPending : .complete
        } catch {
            modelContext.rollback()
            await ShowAssetMediaStore.shared.releaseCommitGate()
            throw error
        }
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
                            allowsInlineSetCurrent && !isCurrent && session.isManuallySelectable(show)
                            ? { selectCurrent(show) }
                            : nil
                        accessibleShowRow(
                            show: show,
                            isCurrent: isCurrent,
                            setCurrentAction: setCurrentAction
                        )
                        .contextMenu {
                            if !isCurrent && session.isManuallySelectable(show) {
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
                            if !isCurrent && session.isManuallySelectable(show) {
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
            session: session,
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
        parts.append(session.phase(for: show, now: Date()).statusText)
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
        guard session.isManuallySelectable(show) else {
            presentToast(.neutral, message: "当前状态不能设为当前现场")
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
            ShowDetailView(
                show: target.show,
                startsEditing: target.startsEditing,
                onDetailVisibilityChange: onDetailVisibilityChange
            )
        }
        .sheet(item: $actionTarget) { show in
            CurrentShowLibraryActionSheet(
                show: show,
                actions: menuActions(for: show),
                onAction: { action in handle(action, for: show) }
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
        .sheet(item: $cancelTarget) { show in
            BSDangerConfirmationSheet(
                title: "取消演出",
                message: "记录为取消后，这场现场仍会保留在“我的现场”中，但不会出现在当前现场。",
                destructiveTitle: "确认取消",
                onConfirm: {
                    cancelTarget = nil
                    updateStatus(show, message: "已记录取消") { show.markCanceled() }
                }
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
            Text("“\(show.name)”删除后无法恢复，也会从足迹统计中移除。")
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
            actionTarget = nil
            updateStatus(show, message: "已恢复原定日期") { show.markScheduled() }
        case .restoreCanceled:
            actionTarget = nil
            updateStatus(show, message: "已撤销取消") { show.markScheduled() }
        case .cancel:
            presentCancel(for: show)
        case .delete:
            presentDelete(show)
        }
    }

    private func present(_ show: Show, editing: Bool) {
        actionTarget = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            destination = .init(show: show, startsEditing: editing)
        }
    }

    private func presentPostpone(for show: Show) {
        actionTarget = nil
        postponeDate = show.postponedDate ?? show.date
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            postponeTarget = show
        }
    }

    private func applyPostponement(to show: Show, newDate: Date?) {
        postponeTarget = nil
        let message = newDate == nil ? "已记录延期，日期待定" : "延期日期已更新"
        updateStatus(show, message: message) { show.markPostponed(newDate: newDate) }
    }

    private func presentCancel(for show: Show) {
        actionTarget = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            cancelTarget = show
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
        guard session.isManuallySelectable(show) else {
            presentToast(.neutral, message: "当前状态不能设为当前现场")
            return
        }
        Task { @MainActor in
            ShowMutationCoordinator.updateCurrentShowFocus(showID: show.id, selections: selections, notificationStates: notificationStates, in: modelContext)
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
                    result == .mediaCleanupPending ? .neutral : .success,
                    message: result == .mediaCleanupPending
                        ? "现场记录已删除，部分本地副本将在下次启动继续清理"
                        : "已删除现场"
                )
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
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 10)
                        .frame(width: 47, height: 63)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("管理 \(show.name)")
            .padding(.trailing, 11)
        }
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
    let actions: [CurrentShowLibraryMenuAction]
    let onAction: (CurrentShowLibraryMenuAction) -> Void

    private var detents: [PresentationDetent] {
        let chromeHeight: CGFloat = 165
        let actionRowHeight: CGFloat = 47
        let preferredHeight = min(420, chromeHeight + actionRowHeight * CGFloat(actions.count))
        return [.height(preferredHeight), .large]
    }

    var body: some View {
        BSDrawerSheet(detents: detents, fitsContent: true) {
            Text(show.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                ForEach(actions, id: \.self) { item in
                    action(item)
                }
            }
        }
    }

    private func action(_ item: CurrentShowLibraryMenuAction) -> some View {
        Button { onAction(item) } label: {
            Label(item.rawValue, systemImage: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(item == .delete ? BSColor.Stage.liveTitle : BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 47)
        }
        .buttonStyle(.plain)
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
