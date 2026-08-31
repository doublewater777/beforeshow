import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var rootShows: [Show]
    @AppStorage(OnboardingCompletionStore.appStorageKey) private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var hasResolvedOnboardingRoute = false
    @State private var isShowingOnboarding = false
    @State private var selectedTab: BeforeShowTab = .current
    /// 仪式结束后,RootView 写入这个目标 → 切到 .footprints → FootprintsView
    /// 在 onChange 触发自己的 push。详见 `presentCeremonyMemoryNavigation`。
    @State private var ceremonyPendingDetail: FootprintDetailDestination?
    /// 长按图标「Pro 限时优惠」Quick Action 的 deep link 路由。
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    /// 点击本地通知的 deep link 路由。RootView 只负责切到「当前」tab，
    /// 具体目标（首页 / 记忆碎片）由 CurrentShowHomeView 消费。
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    /// 语言变化要刷新所有 BSLocalization 文案，但不能换掉 RootView 的身份：
    /// 用 .id(language) 会重建整棵树，把 tab / Settings / 仪式等状态一起丢掉。
    /// 这里只订阅变化触发 body 重算，导航与呈现状态原样保留。
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasFinishedSplash, hasResolvedOnboardingRoute {
                if isShowingOnboarding {
                    OnboardingFlowView(onCompleted: completeOnboarding)
                        .transition(.opacity)
                } else {
                    mainTabView
                        .transition(.opacity)
                }
            }

            if !hasFinishedSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasFinishedSplash = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
        .sheet(isPresented: $proOfferRouter.shouldPresentProSheet) {
            ProPaywallSheetView(initiallyShowsWinback: proOfferRouter.shouldShowWinbackOffer)
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, deepLink in
            // 通知落地的前提是先站在「当前」tab；目标的消费在首页。
            guard deepLink != nil else { return }
            selectedTab = .current
        }
        .task {
            resolveOnboardingRouteIfNeeded()
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
            FootprintDebugSeeder.seedIfRequested(in: modelContext)
            if ProcessInfo.processInfo.arguments.contains("--open-footprints") {
                selectedTab = .footprints
            }
            if ProcessInfo.processInfo.arguments.contains("--open-pro-paywall") {
                ProOfferDeepLinkRouter.shared.routeToPro()
            }
            if ProcessInfo.processInfo.arguments.contains("--open-pro-winback") {
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
        }
        #endif
    }

    private func resolveOnboardingRouteIfNeeded() {
        guard !hasResolvedOnboardingRoute else { return }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--open-onboarding") {
            isShowingOnboarding = true
            hasResolvedOnboardingRoute = true
            return
        }
        if arguments.contains(where: { argument in
            argument.hasPrefix("--seed-")
                || argument == "--open-footprints"
                || argument == "--open-pro-paywall"
                || argument == "--open-pro-winback"
        }) {
            isShowingOnboarding = false
            hasResolvedOnboardingRoute = true
            return
        }
        #endif

        let hasShows = !rootShows.isEmpty
        if OnboardingRoutingPolicy.shouldMigrateExistingUser(
            hasCompleted: hasCompletedOnboarding,
            hasShows: hasShows
        ) {
            hasCompletedOnboarding = true
        }
        isShowingOnboarding = OnboardingRoutingPolicy.shouldPresent(
            hasCompleted: hasCompletedOnboarding,
            hasShows: hasShows
        )
        hasResolvedOnboardingRoute = true
    }

    private func completeOnboarding(showID _: UUID) {
        hasCompletedOnboarding = true
        if reduceMotion {
            isShowingOnboarding = false
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingOnboarding = false
            }
        }
    }

    /// System TabView so iOS 26+ applies Liquid Glass to the tab bar.
    /// Both tabs stay mounted and keep the system tab bar visible across in-tab navigation.
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            CurrentShowHomeView(
                isPlaybackActive: selectedTab == .current,
                ceremonyPendingDetail: $ceremonyPendingDetail
            )
            .tabItem {
                Label(
                    BeforeShowTab.current.localizedTitle,
                    systemImage: BeforeShowTab.current.iconName
                )
            }
            .tag(BeforeShowTab.current)

            FootprintsView(
                pendingDetailTarget: ceremonyPendingDetail
            )
            .tabItem {
                Label(
                    BeforeShowTab.footprints.localizedTitle,
                    systemImage: BeforeShowTab.footprints.iconName
                )
            }
            .tag(BeforeShowTab.footprints)
        }
        // 系统 TabView(Liquid Glass)自带交叉淡入,自定义 transition 会和它打架;
        // 这里只补一个轻触觉,让切 tab 有确认感。
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: ceremonyPendingDetail) { _, newValue in
            // 仪式 sheet 关闭并要求跳到足迹时,切到 footprints tab。
            // FootprintsView 自己的 onChange 监听同一值并触发 push。
            if newValue != nil, selectedTab != .footprints {
                selectedTab = .footprints
            }
        }
    }
}

enum CurrentShowPlaybackPolicy {
    static func isActive(
        baseIsActive: Bool,
        sceneIsActive: Bool,
        hasOverlay: Bool
    ) -> Bool {
        baseIsActive && sceneIsActive && !hasOverlay
    }
}

struct CurrentShowHomeArrival: Hashable {
    enum Phase: Hashable {
        case prepared
        case animating
    }

    let showID: UUID
    var phase: Phase
}

enum CurrentShowHomeArrivalPolicy {
    static func shouldAnimate(newShowID: UUID, currentShowID: UUID?) -> Bool {
        newShowID == currentShowID
    }
}

// MARK: - Current Show Home

private struct CurrentShowHomeView: View {
    var isPlaybackActive = true
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
    @State private var homeArrival: CurrentShowHomeArrival?

    private let session = CurrentShowSession()
    private let formatter = ShowDisplayFormatter()

    private var currentShow: Show? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)
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
                            && !isDetailVisible
                            && !isShowingSettings
                            && !isShowingShowLibrary
                            && !isImportingDynamicCover
                            && !isShowingAddShowCoordinator,
                        candidateShows: shows,
                        onDetailVisibilityChange: { isVisible in
                            isDetailVisible = isVisible
                            onDetailVisibilityChange(isVisible)
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
                        onHomeArrivalFinished: {
                            homeArrival = nil
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
            .sheet(isPresented: $isShowingAddShowCoordinator, onDismiss: {
                beginPreparedHomeArrivalIfPossible()
            }) {
                AddShowCoordinatorSheet { showID in
                    homeArrival = CurrentShowHomeArrival(showID: showID, phase: .prepared)
                }
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
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
                    Task { await reconcileNotificationFocus() }
                }
            }
            .task {
                // 当前现场会随时间自然更替（旧现场过了停留期，下一场接上）。
                // 只有数据变更时才排通知的话，新的当前现场会一条都收不到。
                await reconcileNotificationFocus()
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
                    ?? shows.first(where: { $0.endedAt == nil }) {
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

    /// 按此刻重算当前现场并对齐已排通知。空转很便宜：计划没变时不重写任何东西。
    @MainActor
    private func reconcileNotificationFocus() async {
        await LocalNotificationCenter.shared.reconcileFocus(
            to: currentShow,
            in: ModelContext(modelContext.container)
        )
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

    private func beginPreparedHomeArrivalIfPossible() {
        guard let arrival = homeArrival, arrival.phase == .prepared else { return }
        guard CurrentShowHomeArrivalPolicy.shouldAnimate(
            newShowID: arrival.showID,
            currentShowID: currentShow?.id
        ) else {
            homeArrival = nil
            return
        }
        homeArrival = CurrentShowHomeArrival(showID: arrival.showID, phase: .animating)
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

// MARK: - Current Show Management

/// 当前现场从页头、海报到阶段快捷功能的可复用管理区。
/// 只消费真实 `Show` 与 `CurrentShowTimeState`，不负责下一场、列表或历史内容。
struct CurrentShowManagementSection: View {
    let show: Show
    let formatter: ShowDisplayFormatter
    var isPlaybackActive = true
    let candidateShows: [Show]
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var onAddShow: () -> Void
    var onOpenSettings: () -> Void
    var onOpenShowLibrary: () -> Void
    var onChooseDynamicCover: () -> Void = {}
    var isImportingDynamicCover = false
    var onConfirmEnd: (Date) -> Void
    var homeArrival: CurrentShowHomeArrival?
    var onHomeArrivalFinished: () -> Void = {}
    @Binding var ceremonyLightsOutShowID: UUID?
    @Binding var ceremonySheetShowID: UUID?
    var onCeremonyCommit: (_ rating: Int?, _ note: String?) async throws -> Void
    /// 仪式 sheet 内部按 `×` / 「进入现场回忆」时回调,父视图负责切到足迹并 push 详情。
    var onCeremonySkipToMemory: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: CurrentShowPresentedSheet?
    @State private var pendingMemoryCreate: MemoryCreateSourceOption?
    @State private var installedMapApps: [ExternalMapApp] = []
    @State private var companionErrorMessage: String?
    @State private var isHeaderOverContent = false
    @State private var hasArrivedHero = true
    @State private var hasArrivedCountdown = true
    @State private var hasArrivedActions = true
    @ObservedObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    private var currentTimeState: CurrentShowTimeState { CurrentShowTimeState(show: show, now: Date()) }
    private var currentPhase: HomeShowPhase { HomeShowPhase(timeState: currentTimeState) }

    /// 给仪式 sheet 用的极简快照:只含 `shows`,足以让 `FootprintDetailIdentityBuilder`
    /// 推导出「第 N 场现场」「与X第 N 次见面」。城市/艺人/年份在卡片里不显示,
    /// 不需要完整 archive 统计。
    private func footprintIdentityForCeremony() -> FootprintDetailIdentity {
        let snapshot = FootprintArchiveSnapshot.identityOnly(shows: candidateShows)
        return FootprintDetailIdentityBuilder.make(
            show: show,
            archive: snapshot,
            calendar: show.timingCalendar()
        )
    }

    private var isHeroPlaybackActive: Bool {
        CurrentShowPlaybackPolicy.isActive(
            baseIsActive: isPlaybackActive,
            sceneIsActive: scenePhase == .active,
            hasOverlay: presentedSheet != nil
                || companionErrorMessage != nil
        )
    }

    var body: some View {
        homeContent(now: Date())
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--open-memory-fragments") {
                try? await Task.sleep(nanoseconds: 900_000_000)
                presentedSheet = .memory
            }
        }
        #endif
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .endConfirmation:
                CurrentShowEndConfirmationSheet(
                    showName: show.name,
                    showStart: CurrentShowTimeState.minimumConfirmableEnd(
                        for: show,
                        calendar: show.timingCalendar()
                    ),
                    suggestedEnd: currentTimeState.endBoundary
                        ?? CurrentShowTimeState.effectiveStartTime(
                            for: show,
                            calendar: show.timingCalendar()
                        ),
                    calendar: show.endTimingCalendar(),
                    allowsJustEnded: currentPhase == .live,
                    onConfirm: { date in
                        presentedSheet = nil
                        onConfirmEnd(date)
                    }
                )
            case .companion:
                CurrentShowCompanionSheet(
                    show: show,
                    sharedHistory: companionHistory,
                    isEnded: currentPhase == .ended,
                    coordinator: companionCoordinator
                )
            case .asset(let kind):
                ShowAssetSheet(
                    showID: show.id,
                    showName: show.name,
                    kind: kind,
                    onDetailVisibilityChange: onDetailVisibilityChange
                )
            case .memory:
                MemoryFragmentsSheet(show: show, pendingCreate: pendingMemoryCreate)
            case .memoryCreate:
                MemoryCreateSourceSheet { option in
                    pendingMemoryCreate = option
                    presentedSheet = nil
                }
            case .mapChooser:
                MapChooserSheet(
                    hasDestination: hasMapDestination,
                    destinationLabel: mapDestinationLabel,
                    apps: MapChooserPresentation.visibleApps(
                        hasDestination: hasMapDestination,
                        installed: installedMapApps
                    ),
                    onSelect: { app in
                        presentedSheet = nil
                        openMapApp(app)
                    }
                )
            }
        }
        .fullScreenCover(item: $ceremonyLightsOutShowID, onDismiss: {
            // cover 彻底消失后再升 sheet,转场不重叠,熄灯黑场直接接上 sheet 升起。
            ceremonySheetShowID = show.id
        }) { id in
            DispersalLightsOutOverlay(
                showName: show.name,
                ordinal: footprintIdentityForCeremony().showOrdinal
            ) {
                if ceremonyLightsOutShowID == id {
                    ceremonyLightsOutShowID = nil
                }
            }
        }
        .sheet(item: $ceremonySheetShowID) { id in
            if id == show.id {
                DispersalCeremonySheet(
                    show: show,
                    identity: footprintIdentityForCeremony(),
                    calendar: show.timingCalendar(),
                    onCommit: onCeremonyCommit,
                    onSkipToMemory: {
                        ceremonySheetShowID = nil
                        onCeremonySkipToMemory(show.id)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(BSColor.Stage.background)
                .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            installedMapApps = ExternalMapApp.installed
            // 冷启动点通知：路由早于视图出现，onChange 收不到，这里补一次。
            consumeNotificationDeepLink()
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, _ in
            consumeNotificationDeepLink()
        }
        .onChange(of: presentedSheet) { oldSheet, newSheet in
            if newSheet == nil, oldSheet == .memoryCreate, pendingMemoryCreate != nil {
                presentedSheet = .memory
            }
            if newSheet == nil, oldSheet == .memory {
                pendingMemoryCreate = nil
            }
        }
        .alert(
            BSLocalization.text("同行"),
            isPresented: Binding(
                get: { companionErrorMessage != nil },
                set: { if !$0 { companionErrorMessage = nil } }
            )
        ) {
            Button(BSLocalization.text("知道了"), role: .cancel) { companionErrorMessage = nil }
        } message: {
            Text(companionErrorMessage ?? "")
        }
        .task(id: show.companionCloudRecordName) {
            await companionCoordinator.refreshCompanion(for: show, in: modelContext)
            companionErrorMessage = CompanionHomeMessagePolicy.message(
                accepted: companionCoordinator.consumePendingAcceptMessage(),
                backgroundError: companionCoordinator.lastErrorMessage
            )
        }
        .task(id: homeArrival) {
            await runHomeArrivalIfNeeded()
        }
    }

    @MainActor
    private func runHomeArrivalIfNeeded() async {
        guard let homeArrival, homeArrival.showID == show.id else {
            hasArrivedHero = true
            hasArrivedCountdown = true
            hasArrivedActions = true
            return
        }

        if homeArrival.phase == .prepared {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasArrivedHero = false
                hasArrivedCountdown = false
                hasArrivedActions = false
            }
            return
        }

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.22)) {
                hasArrivedHero = true
                hasArrivedCountdown = true
                hasArrivedActions = true
            }
            try? await Task.sleep(for: .milliseconds(240))
            onHomeArrivalFinished()
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
            hasArrivedHero = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.34)) {
            hasArrivedCountdown = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.3)) {
            hasArrivedActions = true
        }
        try? await Task.sleep(for: .milliseconds(360))
        onHomeArrivalFinished()
    }

    @ViewBuilder
    private func homeContent(now: Date) -> some View {
        let snapshot = HomeHeroSnapshot(show: show, now: now)
        let timeState = snapshot.timeState
        let followUpShows = CurrentShowFollowUpPolicy.laterShows(
            from: candidateShows,
            excluding: show.id,
            now: now
        )
        let canRecordEnd = CurrentShowEndPolicy.canRecordEnd(
            show: show,
            timeState: timeState,
            now: now,
            calendar: show.timingCalendar()
        )
        let phase = HomeShowPhase(timeState: timeState, now: now)
        // V4 封面为居中立起的 3:4 对象(原型 352pt 宽,窄机退回屏宽 - 40)。
        let coverWidth = min(352, max(0, UIScreen.main.bounds.width - 40))

        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding)

                    NavigationLink {
                        ShowDetailView(show: show, onDetailVisibilityChange: onDetailVisibilityChange)
                    } label: {
                        HomeHeroStage(
                            show: show,
                            snapshot: snapshot,
                            coverWidth: coverWidth,
                            isPlaybackActive: isHeroPlaybackActive,
                            reduceMotion: reduceMotion,
                            isImportingDynamicCover: isImportingDynamicCover,
                            onChooseVideo: onChooseDynamicCover,
                            opensDetail: true
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .opacity(hasArrivedHero ? 1 : 0)
                    .scaleEffect(hasArrivedHero ? 1 : 0.94)
                    .offset(y: hasArrivedHero ? 0 : 24)

                    HomeCountdownLockup(
                        show: show,
                        onEndShow: canRecordEnd
                            ? { presentedSheet = .endConfirmation }
                            : nil,
                        onCompanion: { presentedSheet = .companion },
                        onMemoryFragments: {
                            pendingMemoryCreate = nil
                            presentedSheet = .memory
                        },
                        onMemoryCreate: {
                            pendingMemoryCreate = nil
                            presentedSheet = .memoryCreate
                        }
                    )
                        .padding(.horizontal, 21)
                        .padding(.top, 20)
                        .opacity(hasArrivedCountdown ? 1 : 0)
                        .offset(y: hasArrivedCountdown ? 0 : 18)

                    quickActionRow(
                        CurrentShowQuickAction.actions(
                            for: phase,
                            inOpeningMemoryWindow: OpeningMemoryWindow.isActive(
                                now: now,
                                showStart: CurrentShowTimeState.effectiveStartTime(
                                    for: show,
                                    calendar: show.timingCalendar()
                                ),
                                isLive: phase == .live
                            ),
                            canRecordEnd: canRecordEnd
                        )
                    )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 17)
                        .opacity(hasArrivedActions ? 1 : 0)
                        .offset(y: hasArrivedActions ? 0 : 12)

                    if !followUpShows.isEmpty {
                        CurrentShowFollowUpSummary(
                            shows: followUpShows,
                            formatter: formatter,
                            now: now,
                            onOpenShowLibrary: onOpenShowLibrary,
                            onDetailVisibilityChange: onDetailVisibilityChange
                        )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 25)
                        .opacity(hasArrivedActions ? 1 : 0)
                    }
                }
                .padding(.bottom, BSLayout.tabBarContentInset)
                .frame(maxWidth: .infinity)
            }
            .modifier(HomeHeaderScrollObserver(isOverContent: $isHeaderOverContent))

            if isHeaderOverContent {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.88), location: 0),
                        .init(color: Color.black.opacity(0.58), location: 0.52),
                        .init(color: Color.black.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 136)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            managementHeader
                .padding(.horizontal, contentInset)
                .padding(.top, BSLayout.pageHeaderTopPadding)
                .zIndex(1)
        }
    }

    private var managementHeader: some View {
        HStack {
            Text(BSLocalization.text("当前"))
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                headerButton(icon: "gearshape", label: BSLocalization.text("设置"), action: onOpenSettings)
                headerButton(icon: "list.bullet.rectangle", label: BSLocalization.text("全部现场"), action: onOpenShowLibrary)
                headerButton(icon: "plus", label: BSLocalization.text("添加现场"), action: onAddShow)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
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

    private var locationText: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityText = {
            guard let city, !city.isEmpty else { return nil as String? }
            guard let venue, !venue.localizedCaseInsensitiveContains(city) else { return nil as String? }
            return city
        }()

        return [
            venue,
            cityText
        ]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " · ")
    }

    private var routeQuery: String? {
        MapDestinationQuery.make(
            venueAddress: show.venueAddress,
            venueName: show.venueName,
            city: show.city,
            showName: show.name
        )
    }

    private var hasMapDestination: Bool {
        guard let routeQuery else { return false }
        return !routeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 弹窗副标题：优先场馆名，其次城市 / 演出名。
    private var mapDestinationLabel: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let venue, !venue.isEmpty { return venue }
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let city, !city.isEmpty { return city }
        return show.name
    }

    private func quickActionRow(_ actions: [CurrentShowQuickAction]) -> some View {
        HStack(spacing: 8) {
            ForEach(actions, id: \.self) { action in
                Button {
                    performQuickAction(action)
                } label: {
                    quickActionTile(action)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func quickActionTile(_ action: CurrentShowQuickAction) -> some View {
        switch action {
        case .companion:
            CurrentShowQuickActionTile(
                action: action,
                companion: CompanionQuickActionPresentation(
                    status: show.companionStatus,
                    companionNames: show.companionNames,
                    isEnded: currentPhase == .ended
                )
            )
        default:
            CurrentShowQuickActionTile(action: action)
        }
    }

    /// 只处理指向当前现场的通知。指向别的现场时保持 pending 不消费也无意义
    /// （用户已经看到的是另一场），直接丢弃，避免路由卡住后续通知。
    private func consumeNotificationDeepLink() {
        guard let deepLink = notificationRouter.pendingDeepLink else { return }
        guard deepLink.showID == show.id else {
            notificationRouter.consume()
            return
        }
        notificationRouter.consume()

        switch deepLink.destination {
        case .home:
            break
        case .memoryFragments:
            pendingMemoryCreate = nil
            presentedSheet = .memory
        case .memoryCreate:
            pendingMemoryCreate = nil
            presentedSheet = .memoryCreate
        }
    }

    private func performQuickAction(_ action: CurrentShowQuickAction) {
        switch action {
        case .route:
            installedMapApps = ExternalMapApp.installed
            presentedSheet = .mapChooser
        case .companion:
            presentedSheet = .companion
        case .ticket:
            openAsset(.ticket)
        case .timetable:
            openAsset(.timetable)
        case .memoryFragments:
            pendingMemoryCreate = nil
            presentedSheet = .memory
        case .endShow:
            presentedSheet = .endConfirmation
        }
    }

    private func openAsset(_ kind: ShowAssetKind) {
        presentedSheet = .asset(kind)
    }

    private func openMapApp(_ app: ExternalMapApp) {
        guard let query = routeQuery,
              let url = app.openURL(for: query) else { return }
        openURL(url)
    }

    private var companionHistory: [Show] {
        CompanionSharedHistory.shows(
            matching: show,
            from: candidateShows
        )
    }

}

private struct HomeHeaderScrollObserver: ViewModifier {
    @Binding var isOverContent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, y in
                let next = y > 10
                if isOverContent != next {
                    isOverContent = next
                }
            }
        } else {
            content
        }
    }
}

enum CompanionSharedHistory {
    /// Group-level history: completed, confirmed shows whose companion name
    /// sets match exactly. Pairwise counts belong to footprint identity, not here.
    static func shows(matching show: Show, from candidates: [Show]) -> [Show] {
        let names = CompanionNameList.normalized(show.companionNames)
        guard !names.isEmpty else {
            if show.companionStatus == .confirmed, show.endedAt != nil {
                return [show]
            }
            return []
        }

        return candidates
            .filter { candidate in
                candidate.companionStatus == .confirmed
                    && candidate.endedAt != nil
                    && CompanionNameList.isSameGroup(candidate.companionNames, names)
            }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }
}

private struct CurrentShowFollowUpSummary: View {
    let shows: [Show]
    let formatter: ShowDisplayFormatter
    let now: Date
    var onOpenShowLibrary: () -> Void = {}
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("之后还有"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .foregroundColor(BSColor.Stage.muted)
                Text(BSLocalization.format("%lld 场", shows.count))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
                Spacer()
            }

            ForEach(shows.prefix(2)) { show in
                NavigationLink {
                    ShowDetailView(show: show, onDetailVisibilityChange: onDetailVisibilityChange)
                } label: {
                    followUpRow(show)
                }
                .buttonStyle(.plain)
            }

            if shows.count > 2 {
                Button(action: onOpenShowLibrary) {
                    HStack(spacing: 8) {
                        Text(BSLocalization.format("查看我的现场 · %lld 场", shows.count))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(BSColor.Stage.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(BSColor.Stage.accent.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func followUpRow(_ show: Show) -> some View {
        HStack(spacing: 11) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                cornerRadius: 10
            )
            .frame(width: 45, height: 60)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(show.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(summaryMeta(for: show))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(distanceText(to: show))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.name)，\(summaryMeta(for: show))，\(distanceText(to: show))")
    }

    private func summaryMeta(for show: Show) -> String {
        let date = formatter.dateText(for: show)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [date, city].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private func distanceText(to show: Show) -> String {
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current)
        let seconds = max(0, Int(start.timeIntervalSince(now)))
        if seconds >= 86_400 { return BSLocalization.format("%lld 天后", seconds / 86_400) }
        if seconds >= 3_600 { return BSLocalization.format("%lld 小时后", seconds / 3_600) }
        return BSLocalization.format("%lld 分钟后", max(1, seconds / 60))
    }
}

enum CompanionHomeMessagePolicy {
    static func message(accepted: String?, backgroundError _: String?) -> String? {
        accepted
    }
}

enum CurrentShowQuickAction: Hashable {
    case route
    case companion
    case ticket
    case timetable
    case memoryFragments
    case endShow

    var title: String {
        switch self {
        case .route: return BSLocalization.text("路线")
        case .companion: return BSLocalization.text("同行")
        case .ticket: return BSLocalization.text("票根")
        case .timetable: return BSLocalization.text("时刻表")
        case .memoryFragments: return BSLocalization.text("记忆碎片")
        case .endShow: return BSLocalization.text("结束现场")
        }
    }

    var iconName: String {
        switch self {
        case .route: return "map"
        case .companion: return "person.2"
        case .ticket: return "ticket"
        case .timetable: return "list.bullet.rectangle"
        case .memoryFragments: return "photo.on.rectangle.angled"
        case .endShow: return "flag.checkered"
        }
    }

    /// 快捷入口按生命周期排序:主行动已在卡片上,这里保留其余入口,
    /// 但把当前阶段次相关的动作后置,避免 ended 后路线/票根抢占记忆。
    static func actions(
        for phase: HomeShowPhase,
        inOpeningMemoryWindow: Bool = false,
        canRecordEnd: Bool = true
    ) -> [Self] {
        switch phase {
        case .pre:
            return [.route, .ticket, .timetable, .companion, .memoryFragments]
        case .live:
            if inOpeningMemoryWindow {
                var actions: [Self] = [.companion, .memoryFragments, .route, .ticket, .timetable]
                if canRecordEnd {
                    actions.insert(.endShow, at: 0)
                }
                return actions
            }
            return [.companion, .memoryFragments, .route, .ticket, .timetable]
        case .ended:
            return [.memoryFragments, .companion, .route, .ticket, .timetable]
        case .inactive:
            return [.route, .companion, .ticket, .timetable, .memoryFragments]
        }
    }
}

struct CompanionQuickActionPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let companionName: String?
    let companionNames: [String]
    let showsPendingIndicator: Bool
    let showsAvatars: Bool

    init(status: ShowCompanionStatus, companionName: String?, isEnded: Bool) {
        self.init(
            status: status,
            companionNames: CompanionNameList.normalized([companionName].compactMap { $0 }),
            isEnded: isEnded
        )
    }

    init(status: ShowCompanionStatus, companionNames: [String], isEnded: Bool) {
        let names = CompanionNameList.normalized(companionNames)
        let joined = CompanionNameList.joined(names)
        self.companionNames = names
        self.companionName = joined
        switch status {
        case .none:
            title = BSLocalization.text("同行")
            accessibilityLabel = BSLocalization.text("同行，邀请朋友")
            showsPendingIndicator = false
            showsAvatars = false
        case .pending:
            title = BSLocalization.text("待确认")
            accessibilityLabel = joined.map { BSLocalization.format("同行，等待%@确认", $0) } ?? BSLocalization.text("同行，待确认")
            showsPendingIndicator = true
            showsAvatars = false
        case .confirmed:
            let displayName = joined ?? BSLocalization.text("同行者")
            title = isEnded ? BSLocalization.text("共同足迹") : BSLocalization.format("与%@", displayName)
            accessibilityLabel = isEnded
                ? (joined.map { BSLocalization.format("同行，与%@的共同足迹", $0) } ?? BSLocalization.text("同行，共同足迹"))
                : BSLocalization.format("同行，与%@已确认", displayName)
            showsPendingIndicator = false
            showsAvatars = true
        case .canceled:
            title = BSLocalization.text("重新邀请")
            accessibilityLabel = joined.map { BSLocalization.format("同行，重新邀请%@", $0) } ?? BSLocalization.text("同行，重新邀请")
            showsPendingIndicator = false
            showsAvatars = false
        }
    }
}

private struct CurrentShowQuickActionTile: View {
    let action: CurrentShowQuickAction
    var companion: CompanionQuickActionPresentation?

    var body: some View {
        VStack(spacing: 7) {
            if let companion, companion.showsAvatars {
                CompanionAvatarStack(names: companion.companionNames)
            } else {
                Image(systemName: action.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            }
            Text(action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if companion?.showsPendingIndicator == true {
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: BSColor.Stage.accent.opacity(0.5), radius: 5)
                    .padding(11)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(companion?.accessibilityLabel ?? action.title)
    }
}

private struct CompanionAvatarStack: View {
    let names: [String]

    private static let maxVisibleOthers = 3
    private static let palettes: [[Color]] = [
        [BSColor.Stage.accent, BSColor.Stage.glowBlue],
        [BSColor.Accent.violet, BSColor.Stage.accent],
        [BSColor.Accent.warm, BSColor.Accent.violet],
        [BSColor.Stage.glowBlue, BSColor.Accent.warm]
    ]

    var body: some View {
        let visible = Array(CompanionNameList.normalized(names).prefix(Self.maxVisibleOthers))
        let overflow = max(0, CompanionNameList.normalized(names).count - visible.count)
        return HStack(spacing: -8) {
            avatar(BSLocalization.text("我"), colors: Self.palettes[0])
            ForEach(Array(visible.enumerated()), id: \.offset) { index, name in
                avatar(initial(name), colors: Self.palettes[(index + 1) % Self.palettes.count])
            }
            if overflow > 0 {
                avatar("+\(overflow)", colors: [BSColor.Stage.muted, BSColor.Stage.dim])
            }
        }
        .accessibilityHidden(true)
    }

    private func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? BSLocalization.text("友") : String(trimmed.prefix(1))
    }

    private func avatar(_ text: String, colors: [Color]) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(BSColor.Stage.background)
            .frame(width: 25, height: 25)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
            .overlay(Circle().stroke(BSColor.Stage.surface, lineWidth: 2))
    }
}

private struct MapChooserSheet: View {
    let hasDestination: Bool
    let destinationLabel: String
    let apps: [ExternalMapApp]
    let onSelect: (ExternalMapApp) -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "map",
                    title: MapChooserPresentation.title(hasDestination: hasDestination),
                    subtitle: MapChooserPresentation.message(
                        hasDestination: hasDestination,
                        destinationLabel: destinationLabel,
                        installed: apps
                    )
                )

                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index == 0 {
                        Button { onSelect(app) } label: {
                            Label(app.title, systemImage: app.iconName)
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                    } else {
                        Button { onSelect(app) } label: {
                            Label(app.title, systemImage: app.iconName)
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

struct CurrentShowCompanionSheet: View {
    let show: Show
    let sharedHistory: [Show]
    let isEnded: Bool
    let coordinator: CompanionSharingCoordinator

    @Environment(\.modelContext) private var modelContext
    @State private var isShowingHistory = false
    @State private var isPreparingInvite = false
    @State private var isRefreshing = false
    @State private var isCanceling = false
    @State private var errorMessage: String?

    init(
        show: Show,
        sharedHistory: [Show],
        isEnded: Bool,
        coordinator: CompanionSharingCoordinator
    ) {
        self.show = show
        self.sharedHistory = sharedHistory
        self.isEnded = isEnded
        self.coordinator = coordinator
    }

    var body: some View {
        BSDrawerSheet(
            detents: [.medium, .large],
            fitsContent: true
        ) {
            ScrollView {
                VStack(spacing: BSSpacing.lg) {
                    switch show.companionStatus {
                    case .none:
                        invitationContent(isRetry: false)
                    case .pending:
                        pendingContent
                    case .confirmed:
                        confirmedContent
                    case .canceled:
                        invitationContent(isRetry: true)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay {
                if isPreparingInvite {
                    preparingOverlay
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPreparingInvite)
        }
        .alert(
            "同行邀请",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            guard show.companionCloudRecordName != nil else { return }
            await coordinator.refreshCompanion(for: show, in: modelContext)
            if let error = coordinator.consumeLastErrorMessage() {
                errorMessage = error
            }
        }
    }

    private func invitationContent(isRetry: Bool) -> some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "person.2",
                title: isRetry ? BSLocalization.text("邀请未接受") : BSLocalization.text("邀请同行"),
                subtitle: isRetry
                    ? BSLocalization.text("可以通过系统分享重新发送邀请，对方点开链接后加入这场同行。")
                    : BSLocalization.text("通过系统分享邀请朋友。对方接受后，会加入这场同行。")
            )

            Button {
                Task { await sendInvitation(isRetry: isRetry) }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text(CompanionInvitePreparingPresentation.primaryActionTitle(
                            isPreparing: true,
                            isRetry: isRetry
                        ))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(
                        CompanionInvitePreparingPresentation.primaryActionTitle(
                            isPreparing: false,
                            isRetry: isRetry
                        ),
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isPreparingInvite)
        }
    }

    private var pendingContent: some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "hourglass",
                title: pendingTitle,
                subtitle: BSLocalization.text("已通过系统分享发出邀请。对方点开链接并接受后，这里会自动变成已确认。")
            )

            Button {
                Task { await resendInvitation() }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(BSColor.Stage.foreground)
                        Text(CompanionInvitePreparingPresentation.overlayTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(BSLocalization.text("再次发送"), systemImage: "paperplane")
                }
            }
            .buttonStyle(BSSecondaryButtonStyle())
            .disabled(isPreparingInvite || show.companionShareRecordName == nil)

            Button {
                Task { await refreshStatus() }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(BSLocalization.text("刷新状态"), systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isRefreshing)

            destructiveButton("取消邀请") {
                Task { await cancelInvitation() }
            }
            .disabled(isCanceling)
        }
    }

    @ViewBuilder
    private var confirmedContent: some View {
        if isEnded {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "person.2.fill",
                    title: BSLocalization.text("共同足迹"),
                    subtitle: BSLocalization.text("这场现场已经收进你们共同的记录。")
                )

                sharedMemoryCard

                ShareLink(item: sharedFootprintShareText) {
                    Label(BSLocalization.text("分享共同足迹"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        } else {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "person.2.fill",
                    title: BSLocalization.format("与%@同行", displayName),
                    subtitle: BSLocalization.text("这场现场已确认同行。")
                )

                companionMembers

                Text(BSLocalization.format("你们共同看过 %lld 场现场", sharedHistory.count))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)

                if isShowingHistory {
                    historyList
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingHistory = true
                        }
                    } label: {
                        Label(BSLocalization.text("查看共同足迹"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                }

                if show.companionIsOwner != false {
                    Button {
                        Task { await resendInvitation() }
                    } label: {
                        if isPreparingInvite {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(BSLocalization.text("邀请更多"), systemImage: "person.badge.plus")
                        }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                    .disabled(isPreparingInvite || show.companionShareRecordName == nil)
                }

                destructiveButton(show.companionIsOwner == false ? "退出同行" : "取消同行") {
                    Task { await cancelInvitation() }
                }
                .disabled(isCanceling)
            }
        }
    }

    private var companionMembers: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.md) {
                person(name: BSLocalization.text("你"), initial: BSLocalization.text("我"))
                ForEach(Array(memberNames.enumerated()), id: \.offset) { _, name in
                    person(name: name, initial: String(name.prefix(1)))
                }
            }
            .padding(.vertical, BSSpacing.sm)
        }
    }

    private func person(name: String, initial: String) -> some View {
        VStack(spacing: 6) {
            Text(initial)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(BSColor.Stage.background)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [BSColor.Stage.accent, BSColor.Stage.glowBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text("已确认")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(BSColor.Stage.prepare)
        }
    }

    private var sharedMemoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOGETHER · \(String(format: "%02d", sharedHistory.count))")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.accent)
            Text(BSLocalization.format("我们一起看的\n第 %lld 场现场", max(1, sharedHistory.count)))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(show.name)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.lg)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.accent.opacity(0.15), BSColor.Stage.surface],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.accent.opacity(0.20), lineWidth: 1))
    }

    @ViewBuilder
    private var historyList: some View {
        if sharedHistory.isEmpty {
            Text("散场后，共同足迹会从这里开始。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.md)
        } else {
            VStack(spacing: 8) {
                ForEach(sharedHistory.prefix(3)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .foregroundColor(BSColor.Stage.accent)
                        Text(item.name)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(12)
                    .background(BSColor.Stage.surface.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(BSFont.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .foregroundColor(BSColor.Stage.liveTitle)
    }

    private var memberNames: [String] {
        CompanionNameList.normalized(show.companionNames)
    }

    private var displayName: String {
        CompanionNameList.joined(memberNames) ?? BSLocalization.text("同行者")
    }

    private var pendingTitle: String {
        if let names = CompanionNameList.joined(memberNames) {
            return BSLocalization.format("等待%@确认", names)
        }
        return BSLocalization.text("等待确认")
    }

    private var sharedFootprintShareText: String {
        BSLocalization.format("我和%@一起看了 %@。\n这是我们共同记录的第 %lld 场现场。", displayName, show.name, max(1, sharedHistory.count))
    }

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.38)
            VStack(spacing: BSSpacing.sm) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.08)
                Text(CompanionInvitePreparingPresentation.overlayTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(CompanionInvitePreparingPresentation.overlayTitle)
        }
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    @MainActor
    private func sendInvitation(isRetry: Bool, alreadyPreparing: Bool = false) async {
        if !alreadyPreparing {
            guard !isPreparingInvite else { return }
            isPreparingInvite = true
        }
        if isRetry, show.companionShareLocator != nil {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("请先完成取消同步，再重新邀请")
            return
        }
        if show.companionShareLocator != nil {
            await resendInvitation(alreadyPreparing: true)
            return
        }
        guard show.companionCloudRecordName == nil else {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("这场现场已有同行邀请，请先刷新状态")
            return
        }
        await coordinator.refreshAllLinkedShows(in: modelContext)
        if CompanionInviteGate.blocksNewInvite(coordinator.lastErrorKind) {
            isPreparingInvite = false
            errorMessage = coordinator.consumeLastErrorMessage()
            return
        }
        _ = coordinator.consumeLastErrorMessage()
        if show.companionShareLocator != nil {
            await resendInvitation(alreadyPreparing: true)
            return
        }
        do {
            let prepared = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: nil,
                ownerDisplayName: nil,
                in: modelContext
            )
            presentPreparedShare(prepared.shareSystemFields)
        } catch {
            isPreparingInvite = false
            CompanionDebugLog.write("sendInvitation failed: \(error)")
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func resendInvitation(alreadyPreparing: Bool = false) async {
        if !alreadyPreparing {
            guard !isPreparingInvite else { return }
            isPreparingInvite = true
        }
        do {
            let data = try await coordinator.shareSystemFieldsForResend(show: show)
            presentPreparedShare(data)
        } catch let error as CompanionSharingError where error == .sessionNotFound {
            // Only recreate when CloudKit positively reports the share is gone.
            await sendInvitation(isRetry: true, alreadyPreparing: true)
        } catch {
            isPreparingInvite = false
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func presentPreparedShare(_ data: Data) {
        let presented = SystemCloudSharePresenter.present(
            shareData: data,
            containerIdentifier: CloudKitCompanionSharingService.defaultContainerIdentifier,
            onEvent: { event, share, error in
                Task { @MainActor in
                    switch event {
                    case .didSave:
                        await coordinator.handleShareControllerDidSave(
                            share: share,
                            for: show,
                            in: modelContext
                        )
                    case .didStopSharing:
                        await coordinator.handleShareControllerDidStopSharing(
                            for: show,
                            in: modelContext
                        )
                    case .failedToSave:
                        if let error {
                            coordinator.handleShareControllerFailure(error)
                            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
                        }
                    }
                }
            },
            onDismiss: {
                isPreparingInvite = false
                if let error = coordinator.consumeLastErrorMessage() {
                    errorMessage = error
                }
            },
            onPresented: {
                isPreparingInvite = false
            }
        )
        if !presented {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("无法打开系统分享")
        }
    }

    @MainActor
    private func refreshStatus() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await coordinator.refreshCompanion(for: show, in: modelContext)
        if let error = coordinator.consumeLastErrorMessage() {
            errorMessage = error
        }
    }

    @MainActor
    private func cancelInvitation() async {
        isCanceling = true
        defer { isCanceling = false }
        do {
            try await coordinator.cancelCompanion(for: show, in: modelContext)
        } catch {
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }
}

private struct CurrentShowEmptyStateView: View {
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
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )

            Text(BSLocalization.text("先添加一场现场"))
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(BSLocalization.text("把要去的音乐现场放进来，\n慢慢靠近那一场。"))
                .font(BSFont.body)
                .foregroundColor(BSColor.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onAddShow) {
                Text(BSLocalization.text("添加现场"))
                    .font(BSFont.caption)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            }
            .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack {
                Text(BSLocalization.text("当前"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                HStack(spacing: 8) {
                    emptyHeaderButton(icon: "gearshape", label: BSLocalization.text("设置"), action: onOpenSettings)
                    emptyHeaderButton(icon: "list.bullet.rectangle", label: BSLocalization.text("全部现场"), action: onOpenShowLibrary)
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

// MARK: - Debug Sample Seeder

#if DEBUG
@MainActor
private enum DebugSampleShowSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        if ProcessInfo.processInfo.arguments.contains("--seed-app-store-screenshots") {
            seedAppStoreScreenshots(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-current-management-live") {
            seedCurrentManagementLive(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-opening-memory-window") {
            seedCurrentManagementLive(in: modelContext, startedAgo: 12 * 60)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-near") {
            seedUpcomingNear(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-soon") {
            seedUpcomingNear(in: modelContext, offset: 42 * 60 + 17)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-no-cover") {
            seedUpcomingNear(in: modelContext, offset: 42 * 60 + 17, withCover: false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-far") {
            seedUpcomingNear(in: modelContext, offset: 57 * 86_400)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-awaiting-end-confirmation") {
            seedPostEstimatedEnd(in: modelContext, confirmEnd: false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-confirmed-ended") {
            seedPostEstimatedEnd(in: modelContext, confirmEnd: true)
            return
        }

        guard ProcessInfo.processInfo.arguments.contains("--seed-add-show-samples") else {
            return
        }

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            var showsByName = Dictionary(uniqueKeysWithValues: existingShows.map { ($0.name, $0) })
            var seededShows: [Show] = []

            for draft in sampleDrafts {
                if let show = showsByName[draft.name] {
                    apply(draft, to: show)
                    seededShows.append(show)
                } else {
                    let show = try draft.makeShow()
                    modelContext.insert(show)
                    showsByName[show.name] = show
                    seededShows.append(show)
                }
            }

            if let firstShow = seededShows.first {
                let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
                if let selection = selections.first {
                    selection.select(showID: firstShow.id)
                } else {
                    modelContext.insert(CurrentShowSelection(selectedShowID: firstShow.id))
                }
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed add-show samples: \(error)")
        }
    }

    /// App Store 截屏演示包：当前「夜航」+ 两场未来现场 + 记忆碎片。
    /// 封面用自有 `default_cover`，避免真实艺人海报版权风险。
    /// Upsert by name — 不要删掉当前现场，否则已打开的 sheet 会绑到被 cascade 清掉的旧对象。
    static func seedAppStoreScreenshots(in modelContext: ModelContext) {
        let coverURL = installDefaultCoverURL() ?? ""
        let primary = appStorePrimaryDraft(coverURL: coverURL)
        let now = Date()
        let secondaryDrafts: [ShowDraft] = [
            ShowDraft(
                name: "潮汐 Livehouse · 杭州站",
                date: now.addingTimeInterval(18 * 86_400),
                startTime: appStoreWallTime(on: now.addingTimeInterval(18 * 86_400)),
                city: "杭州",
                venueName: "酒球会",
                artists: [ArtistSlot(name: "潮汐", avatarURL: nil)],
                coverImageURL: coverURL,
                source: .manual
            ),
            ShowDraft(
                name: "山海音乐节 · 成都",
                date: now.addingTimeInterval(42 * 86_400),
                startTime: appStoreWallTime(on: now.addingTimeInterval(42 * 86_400)),
                city: "成都",
                venueName: "露天音乐公园",
                artists: [ArtistSlot(name: "山海", avatarURL: nil)],
                coverImageURL: coverURL,
                source: .manual
            )
        ]
        // 足迹页需要已结束现场；全部虚构，避免真实艺人海报/名称风险。
        let endedDrafts: [(ShowDraft, TimeInterval, Int?)] = [
            (
                ShowDraft(
                    name: "南风 Live · 厦门站",
                    date: now.addingTimeInterval(-40 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-40 * 86_400)),
                    city: "厦门",
                    venueName: "岸边音乐空间",
                    artists: [ArtistSlot(name: "南风", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2.5 * 3_600,
                5
            ),
            (
                ShowDraft(
                    name: "极光音乐节 · 昆明",
                    date: now.addingTimeInterval(-120 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-120 * 86_400)),
                    city: "昆明",
                    venueName: "滇池草坪",
                    artists: [
                        ArtistSlot(name: "极光", avatarURL: nil),
                        ArtistSlot(name: "夜航", avatarURL: nil)
                    ],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                5 * 3_600,
                4
            ),
            (
                ShowDraft(
                    name: "回声巡演 · 南京站",
                    date: now.addingTimeInterval(-220 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-220 * 86_400)),
                    city: "南京",
                    venueName: "奥体中心体育馆",
                    artists: [ArtistSlot(name: "回声", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2.5 * 3_600,
                5
            ),
            (
                ShowDraft(
                    name: "潮汐 Livehouse · 上海站",
                    date: now.addingTimeInterval(-300 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-300 * 86_400)),
                    city: "上海",
                    venueName: "育音堂",
                    artists: [ArtistSlot(name: "潮汐", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2 * 3_600,
                3
            )
        ]

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let keepNames = Set(
                [primary.name]
                    + secondaryDrafts.map(\.name)
                    + endedDrafts.map(\.0.name)
            )

            let current: Show
            if let existing = existingShows.first(where: { $0.name == primary.name }) {
                try existing.apply(primary)
                existing.markScheduled()
                existing.clearEnded()
                current = existing
            } else {
                current = try primary.makeShow()
                modelContext.insert(current)
            }

            for draft in secondaryDrafts {
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    existing.markScheduled()
                    existing.clearEnded()
                } else {
                    modelContext.insert(try draft.makeShow())
                }
            }

            for (draft, duration, rating) in endedDrafts {
                let show: Show
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    show = existing
                } else {
                    show = try draft.makeShow()
                    modelContext.insert(show)
                }
                let endAt = (draft.startTime ?? draft.date).addingTimeInterval(duration)
                show.markEnded(at: endAt)
                if let rating {
                    try? show.setClosingRitual(rating: rating, note: nil)
                }
            }

            for show in existingShows where !keepNames.contains(show.name) {
                modelContext.delete(show)
            }

            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: current.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: current.id))
            }

            // 截屏包每次刷新记忆，保证带上图片素材（upsert 场景下旧纯文字碎片会被替换）。
            for fragment in current.memoryFragments {
                modelContext.delete(fragment)
            }
            try seedAppStoreMemoryFragments(for: current, now: now, in: modelContext)

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed app store screenshots: \(error)")
        }
    }

    private static func seedAppStoreMemoryFragments(
        for show: Show,
        now: Date,
        in modelContext: ModelContext
    ) throws {
        let before = try MemoryFragment(
            showID: show.id,
            text: "候场的风有点凉，票根捏在手里才觉得真的要开始了。",
            createdAt: now.addingTimeInterval(-3 * 86_400),
            phase: .before
        )
        before.show = show
        try attachDefaultCoverPhoto(to: before, showID: show.id)
        modelContext.insert(before)

        let live = try MemoryFragment(
            showID: show.id,
            text: "灯暗下来的一刻，整个场馆都安静了。",
            createdAt: now.addingTimeInterval(-2 * 86_400),
            phase: .live
        )
        live.show = show
        try attachDefaultCoverPhoto(to: live, showID: show.id)
        modelContext.insert(live)

        let after = try MemoryFragment(
            showID: show.id,
            text: "散场后还不想离开，想把这一晚多留一会儿。",
            createdAt: now.addingTimeInterval(-86_400),
            phase: .after
        )
        after.show = show
        try attachDefaultCoverPhoto(to: after, showID: show.id)
        modelContext.insert(after)
    }

    private static func attachDefaultCoverPhoto(to fragment: MemoryFragment, showID: UUID) throws {
        guard let image = UIImage(named: "default_cover"),
              let data = image.jpegData(compressionQuality: 0.88) else { return }
        let mediaID = UUID()
        let directory = "\(showID.uuidString)/\(fragment.id.uuidString)"
        let relativePath = "\(directory)/\(mediaID.uuidString).jpg"
        let thumbnailPath = "\(directory)/\(mediaID.uuidString)-thumbnail.jpg"
        let location = MemoryMediaLocation.applicationSupport()
        let originalURL = location.url(for: relativePath)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: originalURL, options: .atomic)
        try data.write(to: location.url(for: thumbnailPath), options: .atomic)
        try fragment.appendMedia(MemoryMediaItem(
            id: mediaID,
            kind: .photo,
            relativePath: relativePath,
            thumbnailRelativePath: thumbnailPath,
            contentTypeIdentifier: UTType.jpeg.identifier,
            videoDuration: nil,
            sortOrder: 0
        ))
    }

    static func appStoreReviewDraft() -> ShowDraft {
        appStorePrimaryDraft(coverURL: installDefaultCoverURL() ?? "")
    }

    private static func appStorePrimaryDraft(coverURL: String) -> ShowDraft {
        let start = appStorePrimaryStartDate()
        return ShowDraft(
            name: "「夜航」巡演 · 上海站",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "回声剧场",
            artists: [ArtistSlot(name: "夜航", avatarURL: nil)],
            coverImageURL: coverURL,
            source: .link,
            recognizedFields: [.name, .date, .startTime, .city, .venueName, .artist]
        )
    }

    private static func appStorePrimaryStartDate() -> Date {
        appStoreWallTime(on: Date().addingTimeInterval(56 * 86_400))
    }

    private static func appStoreWallTime(on day: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return calendar.date(
            from: DateComponents(
                year: parts.year,
                month: parts.month,
                day: parts.day,
                hour: 19,
                minute: 30
            )
        ) ?? day
    }

    private static func installDefaultCoverURL() -> String? {
        guard let image = UIImage(named: "default_cover"),
              let data = image.jpegData(compressionQuality: 0.92) else {
            return nil
        }
        do {
            let directory = try ShowCoverLocalImageStore.directory()
            let url = directory.appendingPathComponent("app-store-yehang-cover.jpg")
            try data.write(to: url, options: .atomic)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    private static func seedUpcomingNear(in modelContext: ModelContext, offset: TimeInterval = 3 * 3_600 + 21 * 60 + 18, withCover: Bool = true) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(offset)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "南京",
            venueName: "南京奥体中心体育场",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: withCover ? "https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?auto=format&fit=crop&w=1200&q=85" : "",
            source: .manual
        )
        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.markScheduled()
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }
            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed upcoming-near sample: \(error)")
        }
    }

    /// 越过估算散场边界(start+默认 4h)的现场:confirmEnd=false → 首页「待确认」;
    /// confirmEnd=true → 用户已确认散场,进入停留期。
    private static func seedPostEstimatedEnd(in modelContext: ModelContext, confirmEnd: Bool) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(-5 * 3_600)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "台北",
            venueName: "台北流行音乐中心",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=900&q=85",
            source: .manual
        )
        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.markScheduled()
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }
            if confirmEnd {
                show.markEnded(at: start.addingTimeInterval(2 * 3_600 + 17 * 60))
            }
            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed post-estimated-end sample: \(error)")
        }
    }

    private static func seedCurrentManagementLive(in modelContext: ModelContext, startedAgo: TimeInterval = 84 * 60) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(-startedAgo)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "台北",
            venueName: "台北流行音乐中心",
            venueAddress: "台北市信义区松寿路 20 号",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: "https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&w=900&q=85",
            source: .manual
        )

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }

            let verificationDrafts = [
                ShowDraft(name: "海风音乐祭", date: now.addingTimeInterval(5 * 86_400), startTime: now.addingTimeInterval(5 * 86_400), city: "新北", venueName: "Zepp New Taipei", artists: [ArtistSlot(name: "海岸线", avatarURL: nil)], source: .manual),
                ShowDraft(name: "城市声浪", date: now.addingTimeInterval(18 * 86_400), startTime: now.addingTimeInterval(18 * 86_400), city: "台中", venueName: "台中 Legacy", artists: [ArtistSlot(name: "午夜电台", avatarURL: nil)], source: .manual),
                ShowDraft(name: "南方夏夜", date: now.addingTimeInterval(42 * 86_400), startTime: now.addingTimeInterval(42 * 86_400), city: "高雄", venueName: "LIVE WAREHOUSE", artists: [ArtistSlot(name: "落日之后", avatarURL: nil)], source: .manual)
            ]
            for draft in verificationDrafts {
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    existing.markScheduled()
                    existing.clearEnded()
                } else {
                    modelContext.insert(try draft.makeShow())
                }
            }

            let endedDraft = ShowDraft(name: "冬日回声", date: now.addingTimeInterval(-10 * 86_400), startTime: now.addingTimeInterval(-10 * 86_400), city: "台北", venueName: "The Wall", artists: [ArtistSlot(name: "微光乐团", avatarURL: nil)], source: .manual)
            if let existing = existingShows.first(where: { $0.name == endedDraft.name }) {
                try existing.apply(endedDraft)
                existing.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
            } else {
                let ended = try endedDraft.makeShow()
                ended.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
                modelContext.insert(ended)
            }

            let canceledDraft = ShowDraft(name: "雨季来信", date: now.addingTimeInterval(28 * 86_400), startTime: now.addingTimeInterval(28 * 86_400), city: "台南", venueName: "漂丿白鹭", artists: [ArtistSlot(name: "海岸信号", avatarURL: nil)], source: .manual)
            if let existing = existingShows.first(where: { $0.name == canceledDraft.name }) {
                try existing.apply(canceledDraft)
                existing.markCanceled()
            } else {
                let canceled = try canceledDraft.makeShow()
                canceled.markCanceled()
                modelContext.insert(canceled)
            }

            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-memory-fragments"),
               show.memoryFragments.isEmpty {
                let samples: [(String, MemoryFragmentPhase, TimeInterval)] = [
                    ("终于到了，外面已经排了很长的队。", .before, -62 * 60),
                    ("灯暗下来的一刻，整个场馆都安静了。", .live, -24 * 60),
                    ("散场后还不想离开，想把这一刻多留一会儿。", .after, 18 * 60)
                ]
                for sample in samples {
                    let fragment = try MemoryFragment(
                        showID: show.id,
                        text: sample.0,
                        createdAt: now.addingTimeInterval(sample.2),
                        phase: sample.1
                    )
                    fragment.show = show
                    modelContext.insert(fragment)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-memory-media"),
               !show.memoryFragments.contains(where: { !$0.mediaItems.isEmpty }) {
                let fragmentID = UUID()
                let relativeDirectory = "\(show.id.uuidString)/\(fragmentID.uuidString)"
                let relativePath = "\(relativeDirectory)/sample.jpg"
                let destination = MemoryMediaLocation.applicationSupport().url(for: relativePath)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { context in
                    UIColor(red: 0.18, green: 0.25, blue: 0.48, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                }
                guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                try data.write(to: destination, options: .atomic)
                let fragment = try MemoryFragment(
                    id: fragmentID,
                    showID: show.id,
                    text: BSLocalization.text("灯亮以后随手留下的一段画面。"),
                    createdAt: now.addingTimeInterval(-8 * 60),
                    phase: .live
                )
                fragment.show = show
                try fragment.appendMedia(MemoryMediaItem(
                    id: UUID(),
                    kind: .photo,
                    relativePath: relativePath,
                    thumbnailRelativePath: nil,
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    videoDuration: nil,
                    sortOrder: 0
                ))
                modelContext.insert(fragment)
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed current management live state: \(error)")
        }
    }

    private static var sampleDrafts: [ShowDraft] {
        [
            ShowDraft(
                name: "周杰伦嘉年华世界巡回演唱会 · 南京站",
                date: date(2026, 9, 24),
                startTime: time(2026, 9, 24, 19, 30),
                city: "南京",
                venueName: "南京奥体中心体育场",
                artists: [ArtistSlot(name: "周杰伦", avatarURL: nil)],
                coverImageURL: "https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp",
                source: .link
            ),
            ShowDraft(
                name: "绿洲音乐节2.0·湖州吴兴站",
                date: date(2026, 6, 27),
                startTime: time(2026, 6, 27, 14, 0),
                city: "湖州",
                venueName: "吴乐湾音乐广场",
                artists: ["刘雨昕", "姚琛", "二手玫瑰", "DOUDOU", "椿乐队", "裁缝铺", "麻园诗人", "梅卡德尔", "石岩", "声音碎片", "声音玩具"]
                    .map { ArtistSlot(name: $0, avatarURL: nil) },
                source: .link
            )
        ]
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func apply(_ draft: ShowDraft, to show: Show) {
        try? show.apply(draft)
        show.markScheduled()
    }
}

/// App Store 截屏用：主屏幕中号 + 锁屏长条静态预览（数据与夜航演示包一致）。
private struct AppStoreWidgetPreviewView: View {
    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(BSLocalization.text("小组件"))
                    .font(BSFont.tag)
                    .tracking(3)
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(BSLocalization.text("不用打开，也在靠近"))
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)

                Text(BSLocalization.text("主屏幕和锁屏，都替你数着那一天。"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    mediumWidget
                    lockScreenWidget
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
    }

    private var mediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离灯亮还有"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.Stage.muted)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("56")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(BSColor.Stage.heroIvory)
                        .monospacedDigit()
                    Text(BSLocalization.text("天"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(BSLocalization.text("「夜航」巡演 · 上海站"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(1)
                    Text(BSLocalization.text("10月14日 19:30 · 回声剧场"))
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(width: 86)
                .clipped()
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.018, green: 0.018, blue: 0.025), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                }
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .frame(height: (UIScreen.main.bounds.width - 44) * (170.0 / 364.0))
        .background {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .overlay(BSColor.Stage.background.opacity(0.82))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.text("主屏幕小组件预览"))
    }

    private var lockScreenWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BSLocalization.format("还有 %lld 天", 56))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("「夜航」巡演 · 上海站 · 10月14日 19:30"))
                .font(.system(size: 10))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.text("锁屏小组件预览"))
    }
}
#endif

#Preview {
    RootView()
}
