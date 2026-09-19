import SwiftData
import SwiftUI
import UIKit

// MARK: - Current Show Management

struct CurrentShowManagementSection: View {
    let show: Show
    let formatter: ShowDisplayFormatter
    var isPlaybackActive = true
    let candidateShows: [Show]
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var onPresentationVisibilityChange: (Bool) -> Void = { _ in }
    var onAddShow: () -> Void
    var onOpenSettings: () -> Void
    var onOpenShowLibrary: () -> Void
    var onChooseDynamicCover: () -> Void = {}
    var isImportingDynamicCover = false
    var onConfirmEnd: (Date) -> Void
    var homeArrival: CurrentShowHomeArrival?
    var onHomeArrivalPrepared: (UUID) -> Void = { _ in }
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
    @State private var homeArrivalFlags = CurrentShowHomeArrivalFlags.arrived
    /// SwiftUI may nil an item binding before the dismissal animation has ended.
    /// Keep this raised until the corresponding onDismiss fires so a pending
    /// arrival never plays underneath a disappearing child-owned presentation.
    @State private var isPresentationVisibilityLatched = false
    @ObservedObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    private var currentTimeState: CurrentShowTimeState { CurrentShowTimeState(show: show, now: Date()) }
    private var currentPhase: HomeShowPhase { HomeShowPhase(timeState: currentTimeState) }

    private var hasPresentationRequest: Bool {
        presentedSheet != nil
            || pendingMemoryCreate != nil
            || companionErrorMessage != nil
            || ceremonyLightsOutShowID != nil
            || ceremonySheetShowID != nil
    }

    private var isPresentationActive: Bool {
        hasPresentationRequest || isPresentationVisibilityLatched
    }

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
            hasOverlay: isPresentationActive
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
        .sheet(item: $presentedSheet, onDismiss: presentedSheetDidDismiss) { sheet in
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
            // Keep the presentation latch raised across the full-screen → sheet
            // handoff so Current never becomes momentarily "visible" in between.
            isPresentationVisibilityLatched = true
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
        .sheet(item: $ceremonySheetShowID, onDismiss: releasePresentationLatchIfPossible) { id in
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
        .onChange(of: presentedSheet, initial: true) { oldSheet, newSheet in
            if newSheet != nil {
                isPresentationVisibilityLatched = true
            }
            if newSheet == nil, oldSheet == .memoryCreate, pendingMemoryCreate != nil {
                presentedSheet = .memory
            }
            if newSheet == nil, oldSheet == .memory {
                pendingMemoryCreate = nil
            }
        }
        .onChange(of: ceremonyLightsOutShowID, initial: true) { _, showID in
            if showID != nil {
                isPresentationVisibilityLatched = true
            }
        }
        .onChange(of: ceremonySheetShowID, initial: true) { _, showID in
            if showID != nil {
                isPresentationVisibilityLatched = true
            }
        }
        .onChange(of: companionErrorMessage, initial: true) { _, message in
            if message != nil {
                isPresentationVisibilityLatched = true
            } else {
                releasePresentationLatchIfPossible()
            }
        }
        .onChange(of: isPresentationActive, initial: true) { _, isActive in
            onPresentationVisibilityChange(isActive)
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
            homeArrivalFlags = .arrived
            return
        }

        if homeArrival.phase == .prepared {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                homeArrivalFlags = .prepared
            }

            // Parent must not advance to `.animating` until this child has
            // consumed `.prepared`. Yield once after the non-animated state write,
            // then report readiness for this exact show identity.
            await Task.yield()
            guard !Task.isCancelled,
                  homeArrivalFlags.isPreparedForAnimation else {
                return
            }
            onHomeArrivalPrepared(homeArrival.showID)
            return
        }

        // `.animating` is only issued after the prepared callback above, so the
        // three surfaces are guaranteed to start hidden rather than collapsing
        // prepared + animating into one SwiftUI update cycle.
        guard homeArrivalFlags.isPreparedForAnimation else { return }

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.22)) {
                homeArrivalFlags = .arrived
            }
            try? await Task.sleep(for: .milliseconds(240))
            onHomeArrivalFinished()
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
            homeArrivalFlags.hasArrivedHero = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.34)) {
            homeArrivalFlags.hasArrivedCountdown = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.3)) {
            homeArrivalFlags.hasArrivedActions = true
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
                    .opacity(homeArrivalFlags.hasArrivedHero ? 1 : 0)
                    .scaleEffect(homeArrivalFlags.hasArrivedHero ? 1 : 0.94)
                    .offset(y: homeArrivalFlags.hasArrivedHero ? 0 : 24)

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
                        },
                        onOpenRoute: embedsRouteInLocation
                            ? { openRouteChooser() }
                            : nil
                    )
                        .padding(.horizontal, 21)
                        .padding(.top, 20)
                        .opacity(homeArrivalFlags.hasArrivedCountdown ? 1 : 0)
                        .offset(y: homeArrivalFlags.hasArrivedCountdown ? 0 : 18)

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
                            canRecordEnd: canRecordEnd,
                            embedsRouteInLocation: embedsRouteInLocation
                        )
                    )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 17)
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                        .offset(y: homeArrivalFlags.hasArrivedActions ? 0 : 12)

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
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                    } else if candidateShows.count > 1 {
                        CurrentShowLibraryEntryTile(
                            totalShowCount: candidateShows.count,
                            onOpenShowLibrary: onOpenShowLibrary
                        )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 25)
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                    }
                }
                .padding(.bottom, 0)
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

    private var embedsRouteInLocation: Bool {
        true
    }

    private func openRouteChooser() {
        installedMapApps = ExternalMapApp.installed
        presentedSheet = .mapChooser
    }

    private var locationText: String {
        ShowIdentityCopy.venueSummary(venue: show.venueName, city: show.city) ?? ""
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
            openRouteChooser()
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

    private func presentedSheetDidDismiss() {
        if presentedSheet != nil || pendingMemoryCreate != nil {
            isPresentationVisibilityLatched = true
            return
        }
        releasePresentationLatchIfPossible()
    }

    private func releasePresentationLatchIfPossible() {
        Task { @MainActor in
            await Task.yield()
            guard !hasPresentationRequest else {
                isPresentationVisibilityLatched = true
                return
            }
            isPresentationVisibilityLatched = false
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
