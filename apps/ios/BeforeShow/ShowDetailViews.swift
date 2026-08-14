import SwiftUI
import SwiftData
import UIKit

enum ShowDetailInformationPolicy {
    static func venueDetail(address: String?, city: String?) -> String? {
        let value = [address, city].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }
}

enum ShowDetailExperienceAction: String, CaseIterable {
    case companion = "同行"
    case memoryFragments = "记忆碎片"

    var iconName: String {
        switch self {
        case .companion: return "person.2"
        case .memoryFragments: return "photo.on.rectangle.angled"
        }
    }
}

struct PostponeShowSheet: View {
    @Binding var newDate: Date
    let calendar: Calendar
    let onUndated: () -> Void
    let onDated: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            BSStageSheetHeader(
                icon: "calendar.badge.clock",
                title: "延期演出",
                subtitle: "选择这场演出目前的延期状态。",
                tint: BSColor.Accent.warm
            )

            BSSurfacePanel {
                DatePicker("新日期", selection: $newDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(BSColor.Accent.violet)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
            }

            VStack(spacing: BSSpacing.sm) {
                Button("日期待定", action: onUndated)
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("按选择日期延期", action: onDated)
                    .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }
}

private struct ConfirmedEndTimeEditorSheet: View {
    let showName: String
    let showStart: Date
    let calendar: Calendar
    let hasConfirmedEnd: Bool
    @Binding var endTime: Date
    let onSave: () -> Void
    let onUndo: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
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

            BSSurfacePanel {
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
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
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
            }
        }
    }
}

struct ShowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
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
    @State private var toast: BSToastPayload?
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
        session.snapshot(for: show)
    }

    private var timeState: CurrentShowTimeState { snapshot.phase }

    private var isCurrentShow: Bool {
        session.isCurrent(show, among: shows, manualSelection: selections.first)
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        detailSummaryCard
                        countdownCard
                        showInformationSection
                        currentDisplaySection
                        eventStatusSection
                        experienceSection
                        assetManagementSection
                        DynamicCoverManagementSection(show: show)
                        confirmedEndSection
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.xs)
                    .padding(.bottom, BSLayout.tabBarContentInset)
                }
                .scrollIndicators(.hidden)
                .bsNavigationScrollEdge()
            }
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        .navigationTitle("现场详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑", systemImage: "square.and.pencil") {
                        presentedSheet = .editor
                    }
                    Button("删除", systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editor:
                ShowDraftEditorView(
                    title: "编辑现场",
                    draft: ShowDraft(show: show),
                    saveTitle: "保存",
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
                MemoryFragmentsSheet(show: show)
            case .companion:
                CurrentShowCompanionSheet(
                    show: show,
                    sharedHistory: companionHistory,
                    isEnded: HomeShowPhase(timeState: timeState) == .ended,
                    coordinator: companionCoordinator
                )
            case .postpone:
                PostponeShowSheet(
                    newDate: $postponeDraft,
                    calendar: show.timingCalendar(),
                    onUndated: {
                        presentedSheet = nil
                        applyStatus(message: "已记录延期，日期待定") {
                            show.markPostponed(newDate: nil)
                        }
                    },
                    onDated: {
                        let newDate = ShowDateSelectionPolicy.normalizedDay(
                            postponeDraft,
                            calendar: show.timingCalendar()
                        )
                        presentedSheet = nil
                        applyStatus(message: "延期日期已更新") {
                            show.markPostponed(newDate: newDate)
                        }
                    }
                )
            }
        }
        .alert(
            DangerConfirmation.deleteShow.title,
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button(DangerConfirmation.deleteShow.confirmTitle, role: .destructive) {
                Task { @MainActor in await deleteShow() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(DangerConfirmation.deleteShow.message)
        }
        .confirmationDialog(
            DangerConfirmation.cancelShow.title,
            isPresented: $isShowingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(DangerConfirmation.cancelShow.confirmTitle, role: .destructive) {
                applyStatus(message: "已记录取消") { show.markCanceled() }
            }
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
    }

    private var detailSummaryCard: some View {
        HStack(spacing: BSSpacing.compact) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                alignment: .top,
                enforcesAspectRatio: false,
                cornerRadius: BSRadius.md
            )
            .frame(width: 74, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(session.phase(for: show, now: Date()).statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusTint)
                    .padding(.horizontal, BSSpacing.sm)
                    .padding(.vertical, BSSpacing.xs)
                    .background(statusTint.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(statusTint.opacity(0.24), lineWidth: 1))

                Text(show.name)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)

                Text(formatter.dateText(for: show))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)

                Text(venueSummary)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var countdownCard: some View {
        HStack(spacing: BSSpacing.compact) {
            Circle()
                .fill(countdownSummary.tint)
                .frame(width: 10, height: 10)
                .background(countdownSummary.tint.opacity(0.08), in: Circle())
                .padding(BSSpacing.sm)

            Text(countdownSummary.title)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            Spacer(minLength: BSSpacing.sm)

            VStack(alignment: .trailing, spacing: BSSpacing.xs) {
                Text(countdownSummary.trailingValue)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(countdownSummary.trailingLabel)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var showInformationSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("演出信息")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            VStack(spacing: 0) {
                detailInfoRow(
                    icon: "calendar",
                    title: formatter.dateText(for: show),
                    subtitle: endTimeDescription
                )
                Divider().overlay(BSColor.Stage.border)
                detailInfoRow(
                    icon: "mappin.and.ellipse",
                    title: show.venueName ?? show.city ?? "未填写场馆",
                    subtitle: venueDetail
                )
                Divider().overlay(BSColor.Stage.border)
                detailInfoRow(
                    icon: "music.note",
                    title: show.artistNames.isEmpty ? "未填写艺人" : show.artistNames.joined(separator: "、"),
                    subtitle: nil,
                    trailing: avatarLeading
                )
            }
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
        }
    }

    private func detailInfoRow(icon: String, title: String, subtitle: String?, trailing: AnyView? = nil) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(title)
                    .font(BSFont.V3.small.weight(.medium))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    /// 详情页艺人行右侧贴一个 40pt Apple Music 头像;没有头像就 nil,保持行高一致。
    private var avatarLeading: AnyView? {
        guard let urlString = show.firstRecognizedArtistAvatarURL,
              let url = URL(string: urlString) else { return nil }
        return AnyView(ArtistAvatarThumb(url: url, size: 40))
    }

    private var currentDisplaySection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("当前展示")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            HStack(spacing: BSSpacing.compact) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 36, height: 36)
                    .background(BSColor.Stage.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                Text(currentDisplayTitle)
                    .font(BSFont.V3.small.weight(.medium))
                    .foregroundColor(BSColor.Stage.foreground)

                Spacer(minLength: BSSpacing.sm)

                if !isCurrentShow && session.isManuallySelectable(show) {
                    Button("设为展示", action: selectCurrent)
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, BSSpacing.compact)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .background(BSColor.Stage.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 1))
                }
            }
            .padding(BSSpacing.compact)
            .background(
                LinearGradient(
                    colors: [BSColor.Stage.accent.opacity(0.06), Color.white.opacity(0.015)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.accent.opacity(0.14), lineWidth: 1))
            .opacity(session.isManuallySelectable(show) || isCurrentShow ? 1 : 0.58)
        }
    }

    private var eventStatusSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("演出状态")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            VStack(spacing: BSSpacing.compact) {
                HStack(spacing: BSSpacing.compact) {
                    Image(systemName: eventStatusIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(eventStatusTint)
                        .frame(width: 36, height: 36)
                        .background(eventStatusTint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    Text(statusTitle)
                        .font(BSFont.V3.small.weight(.medium))
                        .foregroundColor(BSColor.Stage.foreground)

                    Spacer(minLength: 0)
                }

                eventStatusActions
            }
            .padding(BSSpacing.compact)
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
        }
    }

    private var assetManagementSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("现场资料")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            HStack(spacing: BSSpacing.sm) {
                ForEach(ShowAssetManagementPolicy.entries(for: show, assets: showAssets)) { entry in
                    Button {
                        presentedSheet = .asset(entry.kind)
                    } label: {
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Image(systemName: entry.kind.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(BSColor.Stage.accent)
                            Text(entry.kind.title)
                                .font(BSFont.V3.small.weight(.medium))
                                .foregroundColor(BSColor.Stage.foreground)
                            Text(entry.subtitle)
                                .font(BSFont.V3.caption)
                                .foregroundColor(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BSSpacing.compact)
                        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                                .stroke(BSColor.Stage.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("管理\(entry.kind.title)，\(entry.subtitle)")
                }
            }
        }
    }

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("现场体验")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)

            HStack(spacing: BSSpacing.sm) {
                Button {
                    presentedSheet = .companion
                } label: {
                    ShowDetailExperienceTile(
                        action: .companion,
                        title: companionPresentation.title,
                        subtitle: companionPresentationSubtitle
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(companionPresentation.accessibilityLabel)

                Button {
                    presentedSheet = .memory
                } label: {
                    ShowDetailExperienceTile(
                        action: .memoryFragments,
                        title: ShowDetailExperienceAction.memoryFragments.rawValue,
                        subtitle: memoryFragmentsSubtitle
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记忆碎片，\(memoryFragmentsSubtitle)")
            }
        }
    }

    private var companionPresentation: CompanionQuickActionPresentation {
        CompanionQuickActionPresentation(
            status: show.companionStatus,
            companionName: show.companionName,
            isEnded: HomeShowPhase(timeState: timeState) == .ended
        )
    }

    private var memoryFragmentsSubtitle: String {
        memoryFragments.isEmpty ? "记录这一刻" : "\(memoryFragments.count) 条"
    }

    private var companionPresentationSubtitle: String {
        switch show.companionStatus {
        case .none: return "邀请一位朋友"
        case .pending: return "等待确认"
        case .confirmed: return companionPresentation.companionName.map { "与\($0)同行" } ?? "已确认同行"
        case .canceled: return "重新邀请"
        }
    }

    private var companionHistory: [Show] {
        CompanionSharedHistory.shows(matching: show, from: shows)
    }

    @ViewBuilder
    private var eventStatusActions: some View {
        switch show.changeStatus {
        case .scheduled:
            HStack(spacing: BSSpacing.sm) {
                statusActionButton("延期", tint: BSColor.Accent.warm, action: beginPostpone)
                statusActionButton("取消演出", tint: BSColor.Stage.danger) {
                    isShowingCancelConfirmation = true
                }
            }
        case .postponed:
            VStack(spacing: BSSpacing.sm) {
                HStack(spacing: BSSpacing.sm) {
                    statusActionButton("修改延期", tint: BSColor.Accent.warm, action: beginPostpone)
                    statusActionButton("取消演出", tint: BSColor.Stage.danger) {
                        isShowingCancelConfirmation = true
                    }
                }
                statusActionButton(restoreActionTitle, tint: BSColor.Stage.success) {
                    applyStatus(message: restoreSuccessMessage) { show.markScheduled() }
                }
            }
        case .canceled:
            statusActionButton(restoreActionTitle, tint: BSColor.Stage.success) {
                applyStatus(message: restoreSuccessMessage) { show.markScheduled() }
            }
        }
    }

    private func statusActionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(BSFont.V3.caption)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
            .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22), lineWidth: 1))
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var confirmedEndSection: some View {
        if let endedAt = show.endedAt {
            confirmedEndButton(
                title: "修改散场时间",
                value: formattedDate(
                    endedAt,
                    format: "M月d日 HH:mm",
                    calendar: show.endTimingCalendar()
                ),
                icon: "clock.arrow.circlepath"
            ) {
                confirmedEndDraft = endedAt
                presentedSheet = .confirmedEnd
            }
        } else if timeState.kind == .postShow || timeState.kind == .ended {
            confirmedEndButton(
                title: "补记散场时间",
                value: "填写真实散场时间",
                icon: "clock.badge.checkmark"
            ) {
                confirmedEndDraft = suggestedConfirmedEnd
                presentedSheet = .confirmedEnd
            }
        }
    }

    private func confirmedEndButton(
        title: String,
        value: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("散场时间")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.foreground)
            Button(action: action) {
                HStack(spacing: BSSpacing.compact) {
                    Image(systemName: icon)
                        .foregroundColor(BSColor.Stage.accent)
                    Text(title)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Text(value)
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .foregroundColor(BSColor.Stage.dim)
                }
                .font(BSFont.V3.small.weight(.medium))
                .padding(.horizontal, BSSpacing.compact)
                .frame(minHeight: 54)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var venueSummary: String {
        let value = [show.venueName, show.city].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? "场馆待补充" : value
    }

    private var venueDetail: String? {
        ShowDetailInformationPolicy.venueDetail(address: show.venueAddress, city: show.city)
    }

    private var endTimeDescription: String? {
        if let endedAt = show.endedAt {
            return "已于 \(formattedDate(endedAt, format: "M月d日 HH:mm", calendar: show.endTimingCalendar())) 结束"
        }
        if let endTime = timeState.effectiveEndTime {
            return "预计 \(formattedDate(endTime, format: "HH:mm", calendar: show.endTimingCalendar())) 结束"
        }
        return nil
    }

    private var currentDisplayTitle: String {
        if isCurrentShow { return "当前展示中" }
        return session.isManuallySelectable(show) ? "未设为当前" : "暂不可设为当前"
    }

    private var statusTint: Color {
        switch show.changeStatus {
        case .scheduled: return BSColor.Stage.glowBlue
        case .postponed: return BSColor.Accent.warm
        case .canceled: return BSColor.Stage.danger
        }
    }

    private var eventStatusTint: Color {
        switch show.changeStatus {
        case .scheduled: return BSColor.Stage.success
        case .postponed: return BSColor.Accent.warm
        case .canceled: return BSColor.Stage.danger
        }
    }

    private var eventStatusIcon: String {
        switch show.changeStatus {
        case .scheduled: return "checkmark"
        case .postponed: return show.postponedDate == nil ? "ellipsis" : "arrow.clockwise"
        case .canceled: return "xmark"
        }
    }

    private struct DetailCountdownSummary {
        let title: String
        let trailingValue: String
        let trailingLabel: String
        let tint: Color
    }

    private var countdownSummary: DetailCountdownSummary {
        switch show.changeStatus {
        case .canceled:
            return .init(
                title: "这场已经取消",
                trailingValue: "—",
                trailingLabel: "取消",
                tint: BSColor.Stage.danger
            )
        case .postponed where show.postponedDate == nil:
            return .init(
                title: "倒计时暂停",
                trailingValue: "TBD",
                trailingLabel: "待定",
                tint: BSColor.Accent.warm
            )
        case .postponed:
            return .init(
                title: "已延期",
                trailingValue: formattedDate(show.effectiveDate, format: "MM.dd"),
                trailingLabel: "新日期",
                tint: BSColor.Accent.warm
            )
        case .scheduled:
            return .init(
                title: timeState.countdownText,
                trailingValue: formattedDate(show.effectiveDate, format: "MM.dd"),
                trailingLabel: formattedDate(show.effectiveDate, format: "EEE"),
                tint: BSColor.Stage.accent
            )
        }
    }

    private func formattedDate(_ date: Date, format: String, calendar: Calendar? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
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
            return "正常进行中"
        case .postponed:
            return show.postponedDate == nil ? "时间待定" : "已改期"
        case .canceled:
            return "演出已取消"
        }
    }

    private var restoreActionTitle: String {
        "恢复正常状态"
    }

    private var restoreSuccessMessage: String {
        show.changeStatus == .canceled ? "已撤销取消" : "已恢复原定日期"
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
            presentToast(.neutral, message: "当前状态不能设为当前现场")
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
                    message: didSync ? "已设为当前现场" : "已切换现场，同步暂未更新"
                )
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: "切换失败，请重试")
            }
        }
    }

    private func saveConfirmedEnd() {
        guard CurrentShowEndPolicy.isValidConfirmedEnd(confirmedEndDraft, for: show) else {
            presentToast(.failure, message: "散场时间需要在开场后、当前时间前")
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
                    message: didSync ? "散场时间已更新" : "散场时间已保存，同步暂未更新"
                )
            } catch {
                presentToast(.failure, message: "散场时间没有保存，请重试")
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
                        ? "已撤销结束，继续按现场时间计时"
                        : "已撤销结束，同步暂未更新"
                )
            } catch {
                presentToast(.failure, message: "没有撤销成功，请重试")
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
            message: didSync ? "现场信息已更新" : "信息已保存，同步暂未更新"
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
            if result.hasPendingMediaCleanup {
                presentToast(
                    .neutral,
                    message: result.didSync
                        ? "现场记录已删除，部分本地副本将在下次启动继续清理"
                        : "现场记录已删除，本地副本与同步将在稍后继续"
                )
            } else if !result.didSync {
                presentToast(.neutral, message: "现场记录已删除，同步暂未更新")
            }
            dismiss()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "删除失败，请重试")
        }
    }

}

private struct ShowDetailExperienceTile: View {
    let action: ShowDetailExperienceAction
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Image(systemName: action.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)

            Text(title)
                .font(BSFont.V3.small.weight(.medium))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)

            Text(subtitle)
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}
