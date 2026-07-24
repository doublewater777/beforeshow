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
                    VStack {
                        Spacer()
                        BSEmptyPanel(
                        iconName: "music.note.list",
                        title: "我的现场为空",
                        message: "把要去和去过的现场都放进来。添加第一场后，这里会按时间保存你的所有现场。",
                        buttonTitle: "添加现场",
                        buttonIconName: "plus"
                    ) {
                            isShowingAddShowCoordinator = true
                        }
                        Spacer()
                    }
                    .padding(.horizontal, BSSpacing.lg)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: BSSpacing.lg) {
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

                            showGroup(title: "即将开始", shows: upcomingShows)
                            showGroup(title: "已结束", shows: endedShows)
                            showGroup(title: "变更", shows: changedShows)

                            Text("左滑或长按可切换当前现场")
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
            .bsToastOverlay(toast, bottomPadding: 28)
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet {
                    presentToast(.success, message: "已放入当前现场")
                }
            }
        }
    }

    @ViewBuilder
    private func showGroup(title: String, shows: [Show]) -> some View {
        if !shows.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: title)
                VStack(spacing: BSSpacing.sm) {
                    ForEach(shows) { show in
                        let isCurrent = show.id == selectedShowID
                        // Avoid nesting a tappable control inside NavigationLink:
                        // row opens detail; set-current is swipe / context only.
                        NavigationLink {
                            ShowDetailView(show: show)
                        } label: {
                            ShowRowView(
                                show: show,
                                isCurrent: isCurrent,
                                formatter: formatter
                            )
                        }
                        .buttonStyle(.plain)
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
                && (state.kind == .before || state.kind == .today)
        }
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

private struct ShowRowView: View {
    let show: Show
    let isCurrent: Bool
    let formatter: ShowDisplayFormatter

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 1, contentMode: .fill)
                .frame(width: 58, height: 58)
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

                Text(subtitleText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(1)

                if let venueName = show.venueName {
                    Text(venueName)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BSSpacing.sm)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCurrent ? "\(show.name)，当前现场" : show.name)
    }

    /// 变更组用 subtitle 明确区分取消/延期；其余组保持「日期 · 状态」。
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

private struct CurrentShowListHeroCard: View {
    let show: Show
    let formatter: ShowDisplayFormatter

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 16.0 / 10.0,
                contentMode: .fill,
                alignment: .top,
                enforcesAspectRatio: false,
                cornerRadius: BSRadius.lg
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)

            LinearGradient(
                colors: [.clear, .black.opacity(0.38), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(show.name)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(2)
                Text("\(show.venueName ?? show.city ?? "现场") · \(formatter.countdownText(for: show))")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(BSSpacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.brandGradient, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.36), radius: 22, x: 0, y: 14)
    }
}

private struct PostponeShowSheet: View {
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

struct ShowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Query(sort: \Show.date) private var shows: [Show]
    let show: Show

    @State private var isEditing = false
    @State private var showsPostponeDialog = false
    @State private var showsCancelConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var newPostponedDate = Date()
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
                    statusSection
                    deleteSection
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .bsToastOverlay(toast, bottomPadding: 28)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            ShowDraftEditorView(
                title: "编辑现场",
                subtitle: editorSubtitle,
                draft: ShowDraft(show: show),
                saveTitle: "保存"
            ) { draft in
                try await apply(draft)
            }
        }
        .sheet(isPresented: $showsPostponeDialog) {
            PostponeShowSheet(
                newDate: $newPostponedDate,
                onUndated: {
                    showsPostponeDialog = false
                    Task { @MainActor in
                        await updateStatus(message: "已记录延期，日期待定") {
                            show.markPostponed(newDate: nil)
                        }
                    }
                },
                onDated: {
                    showsPostponeDialog = false
                    Task { @MainActor in
                        await updateStatus(message: "延期日期已更新") {
                            show.markPostponed(newDate: newPostponedDate)
                        }
                    }
                },
                onCancel: {
                    showsPostponeDialog = false
                }
            )
        }
        .sheet(isPresented: $showsCancelConfirmation) {
            BSDangerConfirmationSheet(
                title: "记录取消",
                message: "记录为取消后，这场现场仍会保留在“我的现场”中，但不会出现在当前现场。",
                destructiveTitle: "确认取消",
                onConfirm: {
                    showsCancelConfirmation = false
                    Task { @MainActor in
                        await updateStatus(message: "已记录取消") {
                            show.markCanceled()
                        }
                    }
                },
                onCancel: {
                    showsCancelConfirmation = false
                }
            )
        }
        .sheet(isPresented: $showsDeleteConfirmation) {
            BSDangerConfirmationSheet(
                title: "删除现场",
                message: "删除后，这场现场将无法恢复。",
                destructiveTitle: "删除",
                onConfirm: {
                    Task { @MainActor in
                        await deleteShow()
                    }
                },
                onCancel: {
                    showsDeleteConfirmation = false
                }
            )
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
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            BSSectionHeader(title: "现场状态")
            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    HStack(alignment: .top, spacing: BSSpacing.sm) {
                        Image(systemName: statusIconName)
                            .foregroundColor(statusTint)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text(statusTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(BSColor.textPrimary)
                            Text(statusDescription)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: BSSpacing.xs) {
                        if show.changeStatus != .scheduled {
                            changeActionRow(
                                title: restoreActionTitle,
                                systemImage: "arrow.uturn.backward",
                                isDestructive: false
                            ) {
                                Task { @MainActor in
                                    await updateStatus(message: restoreSuccessMessage) {
                                        show.markScheduled()
                                    }
                                }
                            }
                        }

                        if show.changeStatus != .canceled {
                            changeActionRow(
                                title: show.changeStatus == .postponed ? "更新延期信息" : "记录延期",
                                systemImage: "calendar.badge.clock",
                                isDestructive: false
                            ) {
                                newPostponedDate = show.postponedDate ?? show.date
                                showsPostponeDialog = true
                            }

                            changeActionRow(
                                title: "记录取消",
                                systemImage: "xmark.circle",
                                isDestructive: true
                            ) {
                                showsCancelConfirmation = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            BSSectionHeader(title: "更多")
            changeActionRow(
                title: "删除现场",
                systemImage: "trash",
                isDestructive: true
            ) {
                showsDeleteConfirmation = true
            }
        }
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
            return "艺人、日期、时间和场馆变化请使用“编辑信息”。"
        case .postponed:
            if show.postponedDate != nil {
                return "当前按新日期显示和提醒；原定日期仍保留在记录中。"
            }
            return "倒计时和通知已暂停，确定新日期后可以随时补充。"
        case .canceled:
            return "记录仍保留，但不会参与当前现场选择或发送提醒。"
        }
    }

    private var statusIconName: String {
        switch show.changeStatus {
        case .scheduled: return "checkmark.circle.fill"
        case .postponed: return "calendar.badge.clock"
        case .canceled: return "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch show.changeStatus {
        case .scheduled: return BSColor.Accent.prepare
        case .postponed: return BSColor.Accent.warm
        case .canceled: return BSColor.Accent.danger
        }
    }

    private var restoreActionTitle: String {
        show.changeStatus == .canceled ? "撤销取消" : "取消延期，恢复原定日期"
    }

    private var restoreSuccessMessage: String {
        show.changeStatus == .canceled ? "已撤销取消" : "已恢复原定日期"
    }

    private func changeActionRow(
        title: String,
        systemImage: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = isDestructive ? BSColor.Accent.danger : BSColor.textSecondary
        return Button(action: action) {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundColor(tint)
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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

    @MainActor
    private func updateStatus(
        message: String,
        mutation: () -> Void
    ) async {
        mutation()
        if show.changeStatus == .canceled,
           selections.first?.selectedShowID == show.id {
            selections.first?.clearManualSelection()
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "状态没有保存，请重试")
            return
        }

        let didSyncNotifications = await syncNotificationsToCurrentShow()
        presentToast(
            didSyncNotifications ? .success : .neutral,
            message: didSyncNotifications ? message : "\(message)，通知暂未更新"
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
            showsDeleteConfirmation = false
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
        showsDeleteConfirmation = false
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
