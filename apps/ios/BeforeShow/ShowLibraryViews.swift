import SwiftData
import SwiftUI

// MARK: - My Shows List View

struct MyShowsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var isShowingAddShowCoordinator = false

    private let formatter = ShowDisplayFormatter()

    private var selectedShowID: UUID? {
        CurrentShowSelector().selectCurrentShow(from: shows, manualSelection: selections.first)?.id
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
                        message: "把要去和去过的现场都放进来。添加第一场现场后，这里会按时间保存所有演出、音乐节和 Livehouse。",
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
                                }
                                .accessibilityLabel("添加现场")
                            }

                            showGroup(title: "即将开始", shows: upcomingShows)
                            showGroup(title: "已结束", shows: endedShows)
                            showGroup(title: "变更", shows: changedShows)

                            Text("左滑列表项可切换当前现场")
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
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet()
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
                        NavigationLink {
                            ShowDetailView(show: show)
                        } label: {
                            ShowRowView(
                                show: show,
                                isCurrent: show.id == selectedShowID,
                                formatter: formatter
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
        let calendar = Calendar.current
        return shows.sorted { first, second in
            if first.id == currentID { return true }
            if second.id == currentID { return false }
            if first.changeStatus == .canceled, second.changeStatus != .canceled { return false }
            if second.changeStatus == .canceled, first.changeStatus != .canceled { return true }

            let firstState = CurrentShowTimeState(show: first, calendar: calendar, now: now)
            let secondState = CurrentShowTimeState(show: second, calendar: calendar, now: now)
            return abs(firstState.effectiveDate.timeIntervalSince(now))
                < abs(secondState.effectiveDate.timeIntervalSince(now))
        }
    }

    private func timeState(for show: Show, now: Date = Date()) -> CurrentShowTimeState {
        CurrentShowTimeState(show: show, calendar: .current, now: now)
    }

    private func selectCurrent(_ show: Show) {
        let selection = selections.first ?? CurrentShowSelection()
        if selections.isEmpty {
            modelContext.insert(selection)
        }
        selection.select(showID: show.id)
        try? modelContext.save()
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

            VStack(alignment: .leading, spacing: 6) {
                Text(show.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)

                Text("\(formatter.dateText(for: show)) · \(formatter.statusText(for: show))")
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

            Text(show.type.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
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
                Text("\(show.venueName ?? show.city ?? show.type.displayName) · \(formatter.countdownText(for: show))")
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

private struct DetailActionButton: View {
    let iconName: String
    let title: String
    var tint: Color = BSColor.textPrimary
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(tint.opacity(isProminent ? 0.10 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(tint.opacity(isProminent ? 0.24 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PostponeShowSheet: View {
    @Binding var newDate: Date
    let onUndated: () -> Void
    let onDated: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(360)) {
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
                    .tint(BSColor.Accent.video)
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
    let show: Show

    @State private var isEditing = false
    @State private var showsPostponeDialog = false
    @State private var showsCancelConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var newPostponedDate = Date()
    private let formatter = ShowDisplayFormatter()

    private var timeState: CurrentShowTimeState {
        CurrentShowTimeState(show: show)
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    detailHero
                    countdownCard
                    actionGrid
                    toolList

                    Text("艺人、时间和场馆变化请直接编辑现场信息；现场变更只记录延期和取消。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .padding(BSSpacing.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.lg)
                                .stroke(BSColor.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            ShowDraftEditorView(
                title: "编辑现场",
                draft: ShowDraft(show: show),
                saveTitle: "保存"
            ) { draft in
                apply(draft)
            }
        }
        .sheet(isPresented: $showsPostponeDialog) {
            PostponeShowSheet(
                newDate: $newPostponedDate,
                onUndated: {
                    showsPostponeDialog = false
                    show.markPostponed(newDate: nil)
                    try? modelContext.save()
                },
                onDated: {
                    showsPostponeDialog = false
                    show.markPostponed(newDate: newPostponedDate)
                    try? modelContext.save()
                },
                onCancel: {
                    showsPostponeDialog = false
                }
            )
        }
        .sheet(isPresented: $showsCancelConfirmation) {
            BSDangerConfirmationSheet(
                title: "记录取消",
                message: "标记为取消后，这场现场仍会保留在“我的现场”中，但不会出现在当前现场。",
                destructiveTitle: "确认取消",
                onConfirm: {
                    showsCancelConfirmation = false
                    show.markCanceled()
                    try? modelContext.save()
                },
                onCancel: {
                    showsCancelConfirmation = false
                }
            )
        }
        .sheet(isPresented: $showsDeleteConfirmation) {
            BSDangerConfirmationSheet(
                title: "删除现场",
                message: "删除后，这场现场的碎片、计划、准备事项也会一起被删除，且无法恢复。",
                destructiveTitle: "删除",
                onConfirm: {
                    deleteShow()
                },
                onCancel: {
                    showsDeleteConfirmation = false
                }
            )
        }
    }

    private func deleteShow() {
        do {
            try LocalAppDataDeletionService(audioStorage: .applicationSupport()).deleteShow(show, in: modelContext)
            try modelContext.save()
            showsDeleteConfirmation = false
            dismiss()
        } catch {
            showsDeleteConfirmation = false
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
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.32))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BSColor.borderProminent, lineWidth: 1))
                    }
                    .accessibilityLabel("返回")

                    Spacer()

                    Menu {
                        Button("设为当前", action: selectCurrent)
                        Button("编辑信息") {
                            isEditing = true
                        }
                        Button("记录延期") {
                            newPostponedDate = show.postponedDate ?? show.date
                            showsPostponeDialog = true
                        }
                        Button("删除现场", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.32))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BSColor.borderProminent, lineWidth: 1))
                    }
                    .accessibilityLabel("更多")
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
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private var countdownCard: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text(countdownTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)

                HStack(alignment: .lastTextBaseline, spacing: BSSpacing.sm) {
                    Text(timeState.countdownNumber)
                        .font(.system(size: 48, weight: .light))
                        .bsGradientText()
                        .minimumScaleFactor(0.7)

                    Text(timeState.countdownUnit)
                        .font(BSFont.title)
                        .foregroundColor(BSColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var countdownTitle: String {
        switch timeState.kind {
        case .before, .today:
            return "距离开场还有"
        case .postShow, .ended:
            return "开场已经过去"
        case .postponed, .canceled:
            return "当前状态"
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: BSSpacing.sm), count: 4), spacing: BSSpacing.sm) {
            DetailActionButton(iconName: "star.fill", title: "设为当前") { selectCurrent() }
            DetailActionButton(iconName: "square.and.pencil", title: "编辑信息") { isEditing = true }
            DetailActionButton(iconName: "calendar.badge.clock", title: "记录延期") {
                newPostponedDate = show.postponedDate ?? show.date
                showsPostponeDialog = true
            }
            DetailActionButton(iconName: "xmark.octagon.fill", title: "记录取消", tint: Color(red: 1.0, green: 0.42, blue: 0.42), isProminent: true) {
                showsCancelConfirmation = true
            }
            DetailActionButton(iconName: "trash.fill", title: "删除现场", tint: Color(red: 1.0, green: 0.42, blue: 0.42), isProminent: true) {
                showsDeleteConfirmation = true
            }
            if show.changeStatus != .scheduled {
                DetailActionButton(iconName: "arrow.counterclockwise", title: "恢复日期") {
                    show.markScheduled()
                    try? modelContext.save()
                }
            }
        }
    }

    private var toolList: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            BSSectionHeader(title: "工具")
            TonightFirstListenEntryView(show: show)
            NavigationLink { ShowVideosView(show: show) } label: {
                CurrentFeatureRow(iconName: "play.rectangle.fill", title: "现场视频", subtitle: "开场前先看几场真正的现场", accent: BSColor.Accent.video)
            }
            NavigationLink { CandidateSongsView(show: show) } label: {
                CurrentFeatureRow(iconName: "mic.fill", title: "候选曲目", subtitle: "保留、移除、补充推测歌单", accent: BSColor.Accent.candidate)
            }
            NavigationLink { RoundTripPlanView(show: show) } label: {
                CurrentFeatureRow(iconName: "tram.fill", title: "往返计划", subtitle: "去程和返程安排，返程可先未定", accent: BSColor.Accent.travel)
            }
            NavigationLink { ShowPreparationView(show: show) } label: {
                CurrentFeatureRow(iconName: "sparkles", title: "现场准备", subtitle: "天气、装备、礼仪和注意事项", accent: BSColor.Accent.prepare)
            }
            NavigationLink { ShowFragmentListView(show: show) } label: {
                CurrentFeatureRow(iconName: "sparkles.rectangle.stack", title: "现场碎片", subtitle: "留存这一场的照片、视频和语音", accent: BSColor.Accent.fragment)
            }
        }
        .buttonStyle(.plain)
    }

    private func selectCurrent() {
        let selection = selections.first ?? CurrentShowSelection()
        if selections.isEmpty {
            modelContext.insert(selection)
        }
        selection.select(showID: show.id)
        try? modelContext.save()
    }

    private func apply(_ draft: ShowDraft) {
        show.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        show.date = draft.date
        show.startTime = draft.startTime
        show.endDate = draft.endDate
        show.endTime = draft.endTime
        show.city = trimmedOptional(draft.city)
        show.venueName = trimmedOptional(draft.venueName)
        show.artist = trimmedOptional(draft.artist)
        show.seatSection = trimmedOptional(draft.seatSection)
        show.coverImageURL = trimmedOptional(draft.coverImageURL)
        show.artistAvatarURLs = draft.artistAvatarURLs
        show.type = draft.type
        try? modelContext.save()
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
