import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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

struct CurrentShowHomeView: View {
    var isPlaybackActive = true
    var isFeaturePresentationActive = false
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    /// 仪式结束→现场回忆导航:子视图在 onCeremonySkipToMemory 写它,
    /// RootView 监听后切到 .footprints tab。FootprintsView 自己也监听同一 binding。
    @Binding var ceremonyPendingDetail: FootprintDetailDestination?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingAddShowCoordinator = false
    @State private var isShowingAddShowReview = false
    @State private var isShowingWidgetPreview = false
    @State private var toast: BSToastPayload?
    @State private var isShowingSettings = false
    @State private var isShowingShowLibrary = false
    @State private var isShowingDynamicCoverPicker = false
    @State private var selectedDynamicCoverItem: PhotosPickerItem?
    /// 仪式触发链:commit 成功后 → `ceremonyLightsOutShowID` 拉起 fullScreen 熄灯,
    /// 熄灯动画结束只清空前者,由 fullScreenCover 的 onDismiss 再设置 `ceremonySheetShowID`
    /// 拉起仪式 sheet —— dismiss 与 present 严格串行,不会两个转场互相穿插闪屏。
    /// 两份均为 nil = 无仪式在播。
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

    private var currentShow: Show? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)
    }

    private var homeArrival: CurrentShowHomeArrival? {
        homeArrivalLifecycle.arrival
    }

    private var isHomePresentationActive: Bool {
        #if DEBUG
        let debugPresentationActive = isShowingAddShowReview || isShowingWidgetPreview
        #else
        let debugPresentationActive = false
        #endif

        return isDetailVisible
            || isShowingSettings
            || isShowingShowLibrary
            || isShowingDynamicCoverPicker
            || isImportingDynamicCover
            || isShowingAddShowCoordinator
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
        let showsPart = shows
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
        let selectionPart = selections.first?.selectedShowID?.uuidString ?? "-"
        return "\(selectionPart)#\(showsPart)"
    }

    var body: some View {
        NavigationStack {
            // AmbientBackground 的理想宽度可能超过屏幕，这里封顶以免内容被顶出。
            ZStack {
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)
                    .opacity(
                        homeArrival?.phase == .prepared
                            && homeArrival?.showID == currentShow?.id
                            ? 0
                            : 1
                    )
                    .animation(.easeOut(duration: 0.35), value: homeArrival)

                if let show = currentShow {
                    CurrentShowManagementSection(
                        show: show,
                        formatter: formatter,
                        isPlaybackActive: isPlaybackActive
                            && !isFeaturePresentationActive
                            && !isHomePresentationActive,
                        candidateShows: shows,
                        onDetailVisibilityChange: { isVisible in
                            isDetailVisible = isVisible
                            onDetailVisibilityChange(isVisible)
                        },
                        onPresentationVisibilityChange: { isVisible in
                            isManagementPresentationActive = isVisible
                        },
                        onAddShow: { isShowingAddShowCoordinator = true },
                        onOpenSettings: { isShowingSettings = true },
                        onOpenShowLibrary: { isShowingShowLibrary = true },
                        onChooseDynamicCover: presentDynamicCoverPicker,
                        isImportingDynamicCover: isImportingDynamicCover,
                        onConfirmEnd: { endDate in
                            confirmEnd(show, at: endDate)
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
                        },
                        onCeremonySkipToMemory: { showID in
                            if let show = shows.first(where: { $0.id == showID }) {
                                ceremonyPendingDetail = FootprintDetailDestination(show: show)
                            }
                        }
                    )
                } else {
                    CurrentShowEmptyStateView(
                        hasShows: !shows.isEmpty,
                        onAddShow: { isShowingAddShowCoordinator = true },
                        onOpenSettings: { isShowingSettings = true },
                        onOpenShowLibrary: { isShowingShowLibrary = true }
                    )
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width)
            .bsToastOverlay(toast, bottomPadding: 90)
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet()
            }
            #if DEBUG
            .sheet(isPresented: $isShowingAddShowReview) {
                NavigationStack {
                    AddShowFlowView(
                        sheet: .link,
                        prefilledDraft: DebugSampleShowSeeder.appStoreReviewDraft()
                    )
                }
                .preferredColorScheme(.dark)
            }
            .fullScreenCover(isPresented: $isShowingWidgetPreview) {
                AppStoreWidgetPreviewView()
            }
            #endif
            .task(id: widgetSyncFingerprint) {
                WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
            }
            .onChange(of: currentShow?.id, initial: true) { _, newShowID in
                homeArrivalLifecycle.observeCurrentShow(newShowID)
                Task { await requestNotificationPermissionIfEligible() }
            }
            .onChange(of: canStartHomeArrival, initial: true) { _, canStart in
                guard canStart else { return }
                beginPreparedHomeArrivalIfPossible()
                Task { await requestNotificationPermissionIfEligible() }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
                    Task { await reconcileNotificationPortfolio() }
                }
            }
            .task {
                // 当前现场会随时间自然更替（旧现场过了停留期，下一场接上）。
                // 只有数据变更时才排通知的话，新的当前现场会一条都收不到。
                await reconcileNotificationPortfolio()
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $isShowingShowLibrary) {
                NavigationStack {
                    CurrentShowLibraryManagementView(
                        onDetailVisibilityChange: { isVisible in
                            isDetailVisible = isVisible
                            onDetailVisibilityChange(isVisible)
                        }
                    )
                }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("--open-settings") {
                    isShowingSettings = true
                }
                if ProcessInfo.processInfo.arguments.contains("--open-show-library") {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    isShowingShowLibrary = true
                }
                if ProcessInfo.processInfo.arguments.contains("--open-add-show-review") {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    isShowingAddShowReview = true
                }
                if ProcessInfo.processInfo.arguments.contains("--open-widget-preview") {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    isShowingWidgetPreview = true
                }
                // 截图 / 验证用:跳过熄灯动画，直接打开散场评分分档页（默认选中「夯爆了」）。
                if ProcessInfo.processInfo.arguments.contains("--open-dispersal-rating"),
                   let target = shows.first(where: { $0.name == "「夜航」巡演 · 上海站" })
                    ?? shows.first(where: { $0.endedAt == nil })
                    ?? shows.first {
                    try? await Task.sleep(nanoseconds: 900_000_000)
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
                    try? await Task.sleep(nanoseconds: 600_000_000)
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
            reason: .foreground,
            in: ModelContext(modelContext.container)
        )
    }

    /// 系统通知权限只在 Current Show 稳定可见时自动询问一次。
    /// Add Show 结束录入后先完整 dismiss；这里用下一次 actor turn 重新确认页面仍然可见，
    /// 不靠固定延时，也不会与其他 sheet / alert / onboarding 抢 presentation。
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

    private func confirmEnd(_ show: Show, at date: Date) {
        guard CurrentShowEndPolicy.isValidConfirmedEnd(
            date,
            for: show,
            calendar: show.timingCalendar()
        ) else {
            presentToast(.failure, message: BSLocalization.text("散场时间需要在开场后、当前时间前"))
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
                    show.markEnded(at: date)
                }
                presentToast(
                    didSync ? .success : .neutral,
                    message: didSync
                        ? BSLocalization.text("已落幕，散场时间已计入现场记录")
                        : BSLocalization.text("散场时间已保存，同步暂未更新")
                )
                // 仪式与结束现场解耦:即使 commit 同步未更新也已落库,
                // 仍可升起仪式 sheet 让用户选择补写评价。
                if show.endedAt != nil {
                    ceremonyLightsOutShowID = show.id
                }
            } catch {
                presentToast(.failure, message: BSLocalization.text("散场时间没有保存，请重试"))
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

private struct CurrentShowEmptyStateView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenShowLibrary: () -> Void
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))

            Text(BSLocalization.text(hasShows ? "先选择一场现场" : "先添加一场现场"))
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(BSLocalization.text(
                hasShows
                    ? "点「设为当前」或左滑可切换当前现场"
                    : "把要去的音乐现场放进来，\n慢慢靠近那一场。"
            ))
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)

            Button(action: hasShows ? onOpenShowLibrary : onAddShow) {
                Text(BSLocalization.text(hasShows ? "选择现场" : "添加现场"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack {
                Text(BSLocalization.text("当前"))
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(BSColor.Stage.foreground)
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
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
