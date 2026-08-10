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

            BSGlassPanel {
                DatePicker("新日期", selection: $newDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(BSColor.Accent.violet)
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
            }
        }
    }
}

private struct ShowDetailMoreActionsSheet: View {
    let onDelete: () -> Void

    var body: some View {
        BSDrawerSheet(
            detents: [.height(232)],
            background: BSColor.Stage.surfaceRaised,
            fitsContent: true
        ) {
            Text("更多操作")
                .font(BSFont.headline)
                .foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                HStack(spacing: BSSpacing.compact) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(BSColor.Stage.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text("删除记录")
                            .font(BSFont.V3.small.weight(.medium))
                        Text("永久移除这条现场记录")
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    Spacer()
                }
                .foregroundColor(BSColor.Stage.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
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

    @State private var isEditing = false
    @State private var isEditingConfirmedEnd = false
    @State private var isShowingCompanion = false
    @State private var showingAssetKind: ShowAssetKind?
    @State private var isShowingMoreActions = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingPostpone = false
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
                detailNavigationBar

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
            }
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            ShowDraftEditorView(
                title: "编辑现场",
                draft: ShowDraft(show: show),
                saveTitle: "保存",
                statusPillText: session.phase(for: show, now: Date()).statusText,
                isPostponed: show.changeStatus == .postponed
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
                onUndo: undoConfirmedEnd
            )
        }
        .sheet(item: $showingAssetKind) { kind in
            ShowAssetSheet(
                showID: show.id,
                showName: show.name,
                kind: kind,
                onDetailVisibilityChange: onDetailVisibilityChange,
                keepsParentDetailHidden: true
            )
        }
        .sheet(isPresented: $isShowingCompanion) {
            CurrentShowCompanionSheet(
                show: show,
                sharedHistory: companionHistory,
                isEnded: HomeShowPhase(timeState: timeState) == .ended,
                coordinator: companionCoordinator,
                onDismiss: { isShowingCompanion = false }
            )
        }
        .sheet(isPresented: $isShowingMoreActions) {
            ShowDetailMoreActionsSheet(
                onDelete: showDeleteConfirmation
            )
        }
        .sheet(isPresented: $isShowingDeleteConfirmation) {
            BSDangerConfirmationSheet(
                title: "删除这条现场记录？",
                message: "删除后不会出现在“我的现场”和足迹中，此操作无法恢复。",
                destructiveTitle: "确认删除",
                onConfirm: {
                    isShowingDeleteConfirmation = false
                    Task { @MainActor in await deleteShow() }
                }
            )
        }
        .sheet(isPresented: $isShowingPostpone) {
            PostponeShowSheet(
                newDate: $postponeDraft,
                onUndated: {
                    isShowingPostpone = false
                    applyStatus(message: "已记录延期，日期待定") {
                        show.markPostponed(newDate: nil)
                    }
                },
                onDated: {
                    let newDate = postponeDraft
                    isShowingPostpone = false
                    applyStatus(message: "延期日期已更新") {
                        show.markPostponed(newDate: newDate)
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingCancelConfirmation) {
            BSDangerConfirmationSheet(
                title: "取消这场演出？",
                message: "取消后会停止倒计时和提醒，这场仍会保留在“我的现场”。",
                destructiveTitle: "确认取消演出",
                onConfirm: {
                    isShowingCancelConfirmation = false
                    applyStatus(message: "已记录取消") { show.markCanceled() }
                }
            )
        }
        .task {
            if startsEditing {
                isEditing = true
            }
        }
        .onAppear { onDetailVisibilityChange(true) }
        .onDisappear { onDetailVisibilityChange(false) }
    }

    private var detailNavigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Spacer()

            Text("现场详情")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)

            Spacer()

            Button { isShowingMoreActions = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.vertical, BSSpacing.xs)
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
            HStack(alignment: .firstTextBaseline) {
                Text("演出信息")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                Button("编辑") { isEditing = true }
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget)
                    .accessibilityLabel("编辑演出信息")
            }

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
                    title: show.artist ?? "未填写艺人",
                    subtitle: nil
                )
            }
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
        }
    }

    private func detailInfoRow(icon: String, title: String, subtitle: String?) -> some View {
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
        }
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
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
                        showingAssetKind = entry.kind
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
                    isShowingCompanion = true
                } label: {
                    ShowDetailExperienceTile(
                        action: .companion,
                        title: companionPresentation.title,
                        subtitle: companionPresentationSubtitle
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(companionPresentation.accessibilityLabel)

                NavigationLink {
                    MemoryFragmentsView(show: show)
                        .onAppear { onDetailVisibilityChange(true) }
                        .onDisappear { onDetailVisibilityChange(false) }
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
                value: Self.confirmedEndFormatter.string(from: endedAt),
                icon: "clock.arrow.circlepath"
            ) {
                confirmedEndDraft = endedAt
                isEditingConfirmedEnd = true
            }
        } else if timeState.kind == .postShow || timeState.kind == .ended {
            confirmedEndButton(
                title: "补记散场时间",
                value: "填写真实散场时间",
                icon: "clock.badge.checkmark"
            ) {
                confirmedEndDraft = suggestedConfirmedEnd
                isEditingConfirmedEnd = true
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
            return "已于 \(Self.confirmedEndFormatter.string(from: endedAt)) 结束"
        }
        if let endTime = timeState.effectiveEndTime {
            return "预计 \(Self.clockFormatter.string(from: endTime)) 结束"
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
                trailingValue: Self.monthDayFormatter.string(from: show.effectiveDate),
                trailingLabel: "新日期",
                tint: BSColor.Accent.warm
            )
        case .scheduled:
            return .init(
                title: timeState.countdownText,
                trailingValue: Self.monthDayFormatter.string(from: show.effectiveDate),
                trailingLabel: Self.weekdayFormatter.string(from: show.effectiveDate),
                tint: BSColor.Stage.accent
            )
        }
    }

    private static let confirmedEndFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private var suggestedConfirmedEnd: Date {
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current)
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
            ?? Calendar.current.date(byAdding: .day, value: 7, to: show.effectiveDate)
            ?? show.effectiveDate
        isShowingPostpone = true
    }

    private func showDeleteConfirmation() {
        isShowingMoreActions = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            isShowingDeleteConfirmation = true
        }
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
        guard CurrentShowEndPolicy.isValidConfirmedEnd(confirmedEndDraft, for: show) else {
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
