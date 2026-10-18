import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Current Show Home

enum CurrentShowPlaybackPolicy {
    static func isActive(
        baseIsActive: Bool,
        sceneIsActive: Bool,
        hasOverlay: Bool
    ) -> Bool {
        baseIsActive && sceneIsActive && !hasOverlay
    }
}

private enum CurrentShowHomeSheet: String, Identifiable {
    case addCoordinator
    #if DEBUG
    case addReview
    #endif
    case settings
    case showLibrary

    var id: String { rawValue }
}

struct CurrentShowHomeView: View {
    var isPlaybackActive = true
    var isFeaturePresentationActive = false

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LiveModeFocusStore.key, store: LiveModeFocusStore.defaults) private var focusedPerformanceID: String?
    @State private var presentedSheet: CurrentShowHomeSheet?
    #if DEBUG
    @State private var isShowingWidgetPreview = false
    #endif
    @State private var toast: BSToastPayload?
    @State private var isShowingDynamicCoverPicker = false
    @State private var selectedDynamicCoverItem: PhotosPickerItem?
    /// 刚刚散场确认成功后由 `ceremonyLightsOutShowID` 拉起独立 fullScreen 熄灯；
    /// 熄灯结束后再串行切到 `ceremonySheetShowID`。补记散场时间则直接进入仪式 sheet。
    /// 两份均为 nil = 无仪式 presentation。
    @State private var ceremonyLightsOutShowID: UUID?
    @State private var ceremonySheetShowID: UUID?
    @State private var dynamicCoverImportTask: Task<Void, Never>?
    @State private var isImportingDynamicCover = false
    @State private var dynamicCoverErrorMessage: String?
    @State private var isDetailVisible = false
    @State private var isManagementPresentationActive = false
    @State private var isRequestingNotificationPermission = false
    @State private var homeArrivalLifecycle = CurrentShowHomeArrivalLifecycle()

    private let session = CurrentShowSession()
    private let formatter = ShowDisplayFormatter()

    /// 删除提交后 @Query 仍可能有一帧带着已脱离 context 的 Show，读属性会 trap。
    private var liveShows: [Show] {
        shows.filter { $0.modelContext != nil }
    }

    private var currentShow: Show? {
        session.selectCurrentShow(from: liveShows, manualSelection: CurrentShowSelectionStore.canonical(in: selections))
    }

    private var homeArrival: CurrentShowHomeArrival? {
        homeArrivalLifecycle.arrival
    }

    private var isHomePresentationActive: Bool {
        #if DEBUG
        let debugPresentationActive = isShowingWidgetPreview
        #else
        let debugPresentationActive = false
        #endif

        return isDetailVisible
            || presentedSheet != nil
            || isShowingDynamicCoverPicker
            || isImportingDynamicCover
            || dynamicCoverErrorMessage != nil
            || debugPresentationActive
    }

    private var canStartHomeArrival: Bool {
        CurrentShowHomeVisibilityPolicy.isVisible(
            tabIsActive: isPlaybackActive,
            sceneIsActive: scenePhase == .active,
            featurePresentationActive: isFeaturePresentationActive,
            homePresentationActive: isHomePresentationActive,
            managementPresentationActive: isManagementPresentationActive
        )
    }

    /// shows 的增删改 + 手动切换现场,都会改变这个指纹,从而触发 widget 同步。
    private var widgetSyncFingerprint: String {
        let showsPart = liveShows
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
        let selectionPart = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID?.uuidString ?? "-"
        // Unified artist avatars can change without a Show edit; widgets and Live Activity follow them.
        return "\(selectionPart)#\(showsPart)#\(ArtistAvatarResolver.shared.revision)"
    }

    var body: some View {
        NavigationStack {
            // AmbientBackground 的理想宽度可能超过容器，这里封顶以免内容被顶出。
            Group {
                if let show = currentShow {
                    CurrentShowManagementSection(
                        show: show,
                        formatter: formatter,
                        isPlaybackActive: isPlaybackActive
                            && !isFeaturePresentationActive
                            && !isHomePresentationActive,
                        candidateShows: liveShows,
                        onDetailVisibilityChange: { isVisible in
                            isDetailVisible = isVisible
                        },
                        onPresentationVisibilityChange: { isVisible in
                            isManagementPresentationActive = isVisible
                        },
                        onAddShow: { presentedSheet = .addCoordinator },
                        onOpenSettings: { presentedSheet = .settings },
                        onOpenShowLibrary: { presentedSheet = .showLibrary },
                        onSetCurrentShow: selectCurrentShow,
                        onChooseDynamicCover: presentDynamicCoverPicker,
                        isImportingDynamicCover: isImportingDynamicCover,
                        onConfirmEnd: { endDate in
                            await confirmEnd(show, at: endDate)
                        },
                        homeArrival: homeArrival,
                        onHomeArrivalPrepared: { showID in
                            handleHomeArrivalPrepared(showID)
                        },
                        onHomeArrivalFinished: {
                            homeArrivalLifecycle.finish(showID: show.id)
                        },
                        ceremonyLightsOutShowID: $ceremonyLightsOutShowID,
                        ceremonySheetShowID: $ceremonySheetShowID,
                        onCeremonyCommit: { rating, note in
                            try await commitCeremonyData(
                                show: show,
                                rating: rating,
                                note: note
                            )
                        }
                    )
                } else {
                    CurrentShowEmptyStateView(
                        hasShows: !shows.isEmpty,
                        onAddShow: { presentedSheet = .addCoordinator },
                        onOpenSettings: { presentedSheet = .settings },
                        onOpenShowLibrary: { presentedSheet = .showLibrary }
                    )
                }
            }
            .bsAdaptiveContentWidth()
            .background {
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)
                    .opacity(
                        homeArrival?.phase == .prepared
                            && homeArrival?.showID == currentShow?.id
                            ? 0
                            : 1
                    )
                    .animation(.easeOut(duration: 0.35), value: homeArrival)
                    .ignoresSafeArea()
            }
            .containerRelativeFrame(.horizontal)
            .bsToastOverlay(toast, bottomPadding: 90)
            .toolbar(.hidden, for: .navigationBar)
            .bsRootBottomChrome()
            .photosPicker(
                isPresented: $isShowingDynamicCoverPicker,
                selection: $selectedDynamicCoverItem,
                matching: .videos
            )
            .onChange(of: selectedDynamicCoverItem) { _, item in
                guard let item, !isImportingDynamicCover, let show = currentShow else { return }
                dynamicCoverImportTask?.cancel()
                isImportingDynamicCover = true
                dynamicCoverImportTask = Task { @MainActor in
                    await importDynamicCover(item, for: show)
                }
            }
            .alert(
                BSLocalization.text("动态封面没有更新"),
                isPresented: Binding(
                    get: { dynamicCoverErrorMessage != nil },
                    set: { if !$0 { dynamicCoverErrorMessage = nil } }
                )
            ) {
                Button(BSLocalization.text("知道了"), role: .cancel) { dynamicCoverErrorMessage = nil }
            } message: {
                Text(dynamicCoverErrorMessage ?? BSLocalization.text("请重试"))
            }
            #if DEBUG
            .fullScreenCover(isPresented: $isShowingWidgetPreview) {
                LiveAndWidgetShowcaseView()
            }
            #endif
            .task(id: widgetSyncFingerprint) {
                WidgetDataSync.sync(shows: liveShows, manualSelection: CurrentShowSelectionStore.canonical(in: selections))
            }
            .onChange(of: focusedPerformanceID) {
                BeforeShowWidgetKind.reloadAllTimelines()
                WidgetDataSync.sync(shows: liveShows, manualSelection: selections.first)
            }
            .onChange(of: currentShow?.id, initial: true) { _, newShowID in
                homeArrivalLifecycle.observeCurrentShow(newShowID)
            }
            .onChange(of: canStartHomeArrival, initial: true) { _, canStart in
                guard canStart else { return }
                beginPreparedHomeArrivalIfPossible()
            }
            .onChange(of: isPlaybackActive, initial: true) { _, isActive in
                guard isActive else { return }
                Task { await requestNotificationPermissionIfEligible() }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    WidgetDataSync.sync(shows: liveShows, manualSelection: CurrentShowSelectionStore.canonical(in: selections))
                    Task {
                        await refreshAutomaticCurrentShowIfNeeded()
                        await reconcileNotificationPortfolio()
                        await requestNotificationPermissionIfEligible()
                    }
                }
            }
            .task {
                // Reconcile on entry and while the Current tab is mounted. The
                // minute cadence also handles show starts and retention expiry.
                while !Task.isCancelled {
                    await refreshAutomaticCurrentShowIfNeeded()
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        break
                    }
                }
            }
            .task {
                // 通知节点会随时间过期、容量也会释放；页面首次出现时补一次 portfolio 对账。
                await reconcileNotificationPortfolio()
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addCoordinator:
                    AddShowCoordinatorSheet()
                #if DEBUG
                case .addReview:
                    NavigationStack {
                        AddShowFlowView(
                            sheet: .link,
                            prefilledDraft: DebugSampleShowSeeder.appStoreReviewDraft()
                        )
                    }
                    .preferredColorScheme(.dark)
                #endif
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                case .showLibrary:
                    NavigationStack {
                        CurrentShowLibraryManagementView(
                            onDetailVisibilityChange: { isVisible in
                                isDetailVisible = isVisible
                            }
                        )
                    }
                }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("--open-settings") {
                    presentedSheet = .settings
                }
                if ProcessInfo.processInfo.arguments.contains("--open-show-library") {
                    try? await Task.sleep(for: .milliseconds(900))
                    presentedSheet = .showLibrary
                }
                if ProcessInfo.processInfo.arguments.contains("--open-add-show-review") {
                    try? await Task.sleep(for: .milliseconds(900))
                    presentedSheet = .addReview
                }
                if ProcessInfo.processInfo.arguments.contains("--open-widget-preview") {
                    try? await Task.sleep(for: .milliseconds(900))
                    isShowingWidgetPreview = true
                }
                // 截图 / 验证用:跳过熄灯动画，直接打开散场评分分档页（默认选中「夯爆了」）。
                if ProcessInfo.processInfo.arguments.contains("--open-dispersal-rating"),
                   let target = shows.first(where: { $0.name == "「夜航」巡演 · 上海站" })
                    ?? shows.first(where: { $0.endedAt == nil })
                    ?? shows.first {
                    try? await Task.sleep(for: .milliseconds(900))
                    target.markEnded(at: Date())
                    try? target.setClosingRitual(
                        rating: 5,
                        note: "最后一首歌结束的时候，灯亮得特别慢，舍不得走。"
                    )
                    try? modelContext.save()
                    ceremonySheetShowID = target.id
                }
                // 截图 / 验证用:对当前 live 现场直接拉起散场仪式,跳过手动点「结束现场」。
                if ProcessInfo.processInfo.arguments.contains("--auto-fire-dispersal"),
                   let live = shows.first(where: { $0.endedAt == nil }) {
                    try? await Task.sleep(for: .milliseconds(600))
                    live.markEnded(at: Date())
                    try? modelContext.save()
                    ceremonyLightsOutShowID = live.id
                }
            }
            #endif
        }
    }

    private func presentDynamicCoverPicker() {
        guard !isImportingDynamicCover else { return }
        isShowingDynamicCoverPicker = true
    }

    /// 按此刻重算全部 eligible 现场并对齐已排通知。空转很便宜：计划没变时不重写任何东西。
    @MainActor
    private func reconcileNotificationPortfolio() async {
        await LocalNotificationCenter.shared.reconcilePortfolio(
            in: ModelContext(modelContext.container)
        )
    }

    /// 系统通知权限只在用户自然进入 Current 或 App 下一次回到前台时自动询问一次。
    /// 主事务（Add Show / 同行邀请 / 其他 presentation）关闭本身不触发权限请求，
    /// 避免完成一个主要动作后立刻出现第二次确认。
    @MainActor
    private func requestNotificationPermissionIfEligible() async {
        guard !isRequestingNotificationPermission,
              canStartHomeArrival,
              let show = currentShow else {
            return
        }

        await Task.yield()

        guard !isRequestingNotificationPermission,
              canStartHomeArrival,
              currentShow?.id == show.id else {
            return
        }

        // Serialize overlapping identity/visibility triggers before the first await.
        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }

        let center = LocalNotificationCenter.shared
        let authorizationState = await center.authorizationState()

        let schedulingState: NotificationSchedulingState
        do {
            schedulingState = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
        } catch {
            return
        }

        let timeKind = CurrentShowTimeState(
            show: show,
            calendar: show.timingCalendar()
        ).kind
        guard NotificationPermissionPolicy().shouldRequestOnCurrentShow(
            authorizationState: authorizationState,
            hasRequestedPermissionAfterFirstShow: schedulingState.hasRequestedPermissionAfterFirstShow,
            currentShowKind: timeKind,
            isCurrentShowVisible: canStartHomeArrival
        ) else {
            return
        }

        // 系统弹窗一旦触发就视为已经自动询问过；允许/拒绝都不再自动重复。
        schedulingState.recordPermissionRequest()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return
        }

        _ = await center.requestAuthorization()
        await reconcileNotificationPortfolio()
    }

    @MainActor
    private func importDynamicCover(_ item: PhotosPickerItem, for show: Show) async {
        defer {
            selectedDynamicCoverItem = nil
            isImportingDynamicCover = false
            dynamicCoverImportTask = nil
        }
        do {
            try await DynamicCoverImportCoordinator.importVideo(item, for: show, in: modelContext)
        } catch is CancellationError {
            return
        } catch let error as DynamicCoverMediaStoreError {
            dynamicCoverErrorMessage = DynamicCoverErrorMessagePolicy.message(for: error)
        } catch {
            dynamicCoverErrorMessage = BSLocalization.text("视频没有载入，请重试。")
        }
    }

    private func handleHomeArrivalPrepared(_ showID: UUID) {
        homeArrivalLifecycle.childDidPrepare(showID: showID)
        beginPreparedHomeArrivalIfPossible()
    }

    private func beginPreparedHomeArrivalIfPossible() {
        _ = homeArrivalLifecycle.beginAnimationIfPossible(
            currentShowID: currentShow?.id,
            isVisible: canStartHomeArrival
        )
    }

    private func commitCeremonyData(show: Show, rating: Int?, note: String?) async throws {
        _ = try await ShowMutationCoordinator.commitClosingRitual(
            rating: rating,
            note: note,
            show: show,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
    }

    @MainActor
    private func refreshAutomaticCurrentShowIfNeeded() async {
        let selection = CurrentShowSelectionStore.canonical(in: selections)
        // Legacy selections are manual, and must not be silently converted.
        if let selection, selection.isManual != false { return }
        let candidate = InitialCurrentShowPolicy().candidate(
            from: liveShows,
            retaining: selection?.selectedShowID
        )
        guard selection?.selectedShowID != candidate?.id else { return }
        do {
            let state = try ShowMutationCoordinator.commitCurrentShowState(
                shows: liveShows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )
            _ = await ShowMutationCoordinator.syncPostCommit(state, in: modelContext)
        } catch {
            modelContext.rollback()
        }
    }

    private func selectCurrentShow(_ target: Show) {
        guard session.isManuallySelectable(target) else {
            presentToast(.neutral, message: BSLocalization.text("这场不能设为当前现场"))
            return
        }

        Task { @MainActor in
            do {
                let didSync = try await ShowMutationCoordinator.selectCurrentShow(
                    showID: target.id,
                    shows: liveShows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext,
                    session: session
                )
                presentToast(
                    didSync ? .success : .neutral,
                    message: didSync
                        ? BSLocalization.text("已设为当前现场")
                        : BSLocalization.text("已切换现场，同步暂未更新")
                )
            } catch {
                modelContext.rollback()
                presentToast(.failure, message: BSLocalization.text("切换失败，请重试"))
            }
        }
    }

    @MainActor
    private func confirmEnd(_ show: Show, at date: Date) async -> Bool {
        guard CurrentShowEndPolicy.isValidConfirmedEnd(
            date,
            for: show,
            calendar: show.timingCalendar()
        ) else {
            presentToast(.failure, message: BSLocalization.text("散场时间需要在开场后、当前时间前"))
            return false
        }

        do {
            // The lights-out / ceremony that follows is the feedback; no toast in front of it.
            _ = try await ShowMutationCoordinator.commitCurrentShowChange(
                shows: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session
            ) {
                show.markEnded(at: date)
            }
            if show.endedAt != nil { ProductAnalytics.capture(.showEndedConfirmed(showID: show.id)) }
            return show.endedAt != nil
        } catch {
            presentToast(.failure, message: BSLocalization.text("散场时间没有保存，请重试"))
            return false
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
}

private struct CurrentShowEmptyStateView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenShowLibrary: () -> Void

    private var message: String {
        BSLocalization.text(
            hasShows
                ? "从你的现场中选择一个，设为当前"
                : "把要去的音乐现场放进来，\n慢慢靠近那一场。"
        )
    }

    var body: some View {
        BSRootEmptyState(
            iconSystemName: "sparkles",
            title: BSLocalization.text(hasShows ? "选择当前现场" : "先添加一场现场"),
            message: message,
            actionTitle: BSLocalization.text(hasShows ? "选择现场" : "添加现场"),
            action: hasShows ? onOpenShowLibrary : onAddShow
        )
        .overlay(alignment: .top) {
            HStack {
                Text(BSLocalization.text("当前"))
                    .font(BSFont.pageTitle)
                    .tracking(-0.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                HStack(spacing: 8) {
                    if hasShows {
                        emptyHeaderButton(
                            icon: "list.bullet.rectangle",
                            label: BSLocalization.text("全部现场"),
                            action: onOpenShowLibrary
                        )
                    }
                    emptyHeaderButton(icon: "gearshape", label: BSLocalization.text("设置"), action: onOpenSettings)
                    emptyHeaderButton(icon: "plus", label: BSLocalization.text("添加现场"), action: onAddShow)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }

    private func emptyHeaderButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
