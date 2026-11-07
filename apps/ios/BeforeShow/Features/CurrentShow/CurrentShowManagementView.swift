import SwiftData
import SwiftUI

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
    var onSetCurrentShow: (Show) -> Void = { _ in }
    var onChooseDynamicCover: () -> Void = {}
    var isImportingDynamicCover = false
    var onConfirmEnd: (Date) async -> Bool
    var homeArrival: CurrentShowHomeArrival?
    var onHomeArrivalPrepared: (UUID) -> Void = { _ in }
    var onHomeArrivalFinished: () -> Void = {}
    @Binding var ceremonyLightsOutShowID: UUID?
    @Binding var ceremonySheetShowID: UUID?
    var onCeremonyCommit: (_ rating: Int?, _ note: String?, _ generatesCard: Bool?) async throws -> Void
    var weather: ShowWeatherDTO? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Query private var recommendationRecords: [FeatureRecommendationRecord]
    @Query private var notificationRecords: [ShowNotificationScheduleRecord]
    @AppStorage(FeatureUsageEnvironment.widgetKey) private var hasInstalledWidget = false
    @AppStorage(FeatureUsageEnvironment.iCloudKey) private var isICloudAvailable = false
    @State var presentedSheet: CurrentShowPresentedSheet?
    @State var pendingMemoryCreate: MemoryCreateSourceOption?
    @State private var pendingConfirmedEndDate: Date?
    @State private var pendingEndIntent: CurrentShowEndConfirmationIntent?
    @State private var installedMapApps: [ExternalMapApp] = []
    @State private var isHeaderOverContent = false
    @AppStorage(LiveModeFocusStore.key, store: LiveModeFocusStore.defaults) private var focusedPerformanceID: String?
    @State private var avatars = TimetableArtistAvatarStore()
    @State private var homeArrivalFlags = CurrentShowHomeArrivalFlags.arrived
    /// SwiftUI may nil an item binding before the dismissal animation has ended.
    /// Keep this raised until the corresponding onDismiss fires so a pending
    /// arrival never plays underneath a disappearing child-owned presentation.
    @State private var isPresentationVisibilityLatched = false
    @State var notificationRouter = NotificationDeepLinkRouter.shared

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    private var currentTimeState: CurrentShowTimeState { CurrentShowTimeState(show: show, now: Date()) }
    var currentPhase: HomeShowPhase { HomeShowPhase(timeState: currentTimeState) }

    private var hasPresentationRequest: Bool {
        presentedSheet != nil
            || pendingMemoryCreate != nil
            || ceremonyLightsOutShowID != nil
            || ceremonySheetShowID != nil
    }

    private var isPresentationActive: Bool {
        hasPresentationRequest || isPresentationVisibilityLatched
    }

    /// 给仪式 sheet 用的极简身份快照：只需从 `shows` 推导「第 N 场现场」
    /// 与同行次数；日期、城市和艺人直接来自当前 `show`，不需要完整 archive 统计。
    private func footprintIdentityForCeremony() -> FootprintDetailIdentity {
        let snapshot = FootprintArchiveSnapshot.identityOnly(shows: attachedCandidateShows)
        return FootprintDetailIdentityBuilder.make(
            show: show,
            archive: snapshot,
            calendar: show.timingCalendar()
        )
    }

    var isHeroPlaybackActive: Bool {
        CurrentShowPlaybackPolicy.isActive(
            baseIsActive: isPlaybackActive,
            sceneIsActive: scenePhase == .active,
            hasOverlay: isPresentationActive
        )
    }

    var liveBody: some View {
        CurrentShowLiveTimetableContent(show: show, isActive: isHeroPlaybackActive) { now, liveState in
            GeometryReader { geometry in
                homeContent(now: now, topInset: geometry.safeAreaInsets.top, liveState: liveState)
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--open-memory-fragments") {
                try? await Task.sleep(for: .milliseconds(900))
                presentedSheet = .memory
            }
            if ProcessInfo.processInfo.arguments.contains("--open-timetable") {
                try? await Task.sleep(for: .milliseconds(1500))
                presentedSheet = .asset(.timetable)
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
                    calendar: show.timingFields.endEventCalendar(fallback: .current),
                    allowsJustEnded: currentPhase == .live,
                    onConfirm: { date, intent in
                        pendingConfirmedEndDate = date
                        pendingEndIntent = intent
                        presentedSheet = nil
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
            case .widgetGuide:
                CurrentShowClosableSheet { WidgetSettingsView() }
            case .footprint:
                CurrentShowClosableSheet {
                    FootprintDetailView(
                        show: show,
                        archive: FootprintArchiveSnapshot.identityOnly(shows: attachedCandidateShows)
                    )
                }
            case .weatherDetail:
                CurrentShowWeatherSheet(
                    show: show,
                    initialWeather: weather,
                    venueName: show.venueName,
                    city: show.city
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
                    onCommit: onCeremonyCommit
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(BSColor.Stage.background)
                .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            installedMapApps = ExternalMapApp.installed
        }
        // 通知转来的当前现场落点等首页真正可见再打开，不打断正在进行的编辑。
        .onChange(of: notificationRouter.currentShowAction, initial: true) { _, _ in
            consumeCurrentShowActionIfVisible()
        }
        .onChange(of: isHeroPlaybackActive) { _, _ in
            consumeCurrentShowActionIfVisible()
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
        .onChange(of: isPresentationActive, initial: true) { _, isActive in
            onPresentationVisibilityChange(isActive)
        }
        .task(id: show.companionCloudRecordName) {
            await companionCoordinator.refreshCompanion(for: show, in: modelContext)
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
    private func homeContent(now: Date, topInset: CGFloat, liveState: LiveModeState?) -> some View {
        let snapshot = HomeHeroSnapshot(show: show, now: now)
        let timeState = snapshot.timeState
        let followUpShows = CurrentShowFollowUpPolicy.laterShows(
            from: attachedCandidateShows,
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
        let liveTimetable = liveState == nil ? nil : show.timetable
        // 与倒计时卡共用同一次推荐决策；现场模式只展示时刻表，不消费推荐。
        let recommendation = liveState == nil ? resolvedRecommendation(snapshot: snapshot) : nil
        let displayedPrimaryAction: HomeCountdownLockup.PrimaryAction? = liveState == nil
            ? HomeCountdownLockup.primaryAction(
                phase: phase,
                timeState: timeState,
                hasConfirmedEnd: show.endedAt != nil,
                hasEndHandler: canRecordEnd,
                // The route has its own map module; it never takes the main button.
                hasRouteHandler: false,
                recommendation: recommendation
            )
            : nil

        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                ScrollViewReader { scrollProxy in
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding)

                    let screens = liveState.flatMap(HomeStageScreens.resolve)
                    let hero = HomeStageHero(
                        show: show,
                        snapshot: snapshot,
                        isPlaybackActive: isHeroPlaybackActive,
                        reduceMotion: reduceMotion,
                        isImportingDynamicCover: isImportingDynamicCover, onChooseVideo: onChooseDynamicCover,
                        topExtension: topInset + BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding + 18,
                        screens: liveTimetable == nil ? nil : screens,
                        livePhase: liveState?.phase,
                        timetable: liveTimetable,
                        avatars: avatars,
                        onOpenTimetable: { presentedSheet = .asset(.timetable) },
                        onFocus: { focusedPerformanceID = $0.uuidString }
                    )
                    Group {
                        if screens != nil, liveTimetable != nil {
                            hero
                        } else {
                            NavigationLink {
                                ShowDetailView(show: show, onDetailVisibilityChange: onDetailVisibilityChange)
                            } label: {
                                hero
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 18)
                    .opacity(homeArrivalFlags.hasArrivedHero ? 1 : 0)
                    .scaleEffect(homeArrivalFlags.hasArrivedHero ? 1 : 0.94)
                    .offset(y: homeArrivalFlags.hasArrivedHero ? 0 : 24)

                    let allActions = CurrentShowQuickAction.deduplicated(
                        CurrentShowQuickAction.actions(
                            for: phase,
                            canRecordEnd: canRecordEnd && liveState?.phase != .fullyEnded,
                            isPostShowRetention: timeState.kind == .postShow && show.endedAt != nil,
                            hasCompletedDispersalCeremony: show.hasCompletedDispersalCeremony
                        ),
                        primaryAction: displayedPrimaryAction
                    )

                    Group {
                        if let liveState, let timetable = liveTimetable {
                            HomeLiveModeView(show: show, timetable: timetable, state: liveState, avatars: avatars, onEndShow: canRecordEnd ? { presentedSheet = .endConfirmation } : nil) { presentedSheet = .asset(.timetable) }
                        } else {
                            CurrentShowCountdownCard(
                                show: show,
                                snapshot: snapshot,
                                recommendation: recommendation,
                                isVisible: isHeroPlaybackActive,
                                onRecommendation: performRecommendation,
                                onEndShow: canRecordEnd
                                    ? { presentedSheet = .endConfirmation }
                                    : nil,
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
                            .id("live-section")
                        }
                    }
                    .padding(.horizontal, contentInset)
                    // The countdown is printed on the stage lip, over the crowd.
                    .padding(.top, liveTimetable == nil ? -46 : 4)
                    .opacity(homeArrivalFlags.hasArrivedCountdown ? 1 : 0)
                    .offset(y: homeArrivalFlags.hasArrivedCountdown ? 0 : 18)

                    CurrentShowActionModules(show: show, actions: allActions, companion: companionPresentation, now: now, routeIsProminent: phase == .pre, timetableIsLive: liveTimetable != nil, perform: performQuickAction)
                        .padding(.horizontal, contentInset)
                        .padding(.top, 28)
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                        .offset(y: homeArrivalFlags.hasArrivedActions ? 0 : 12)

                    if !followUpShows.isEmpty {
                        CurrentShowFollowUpSummary(
                            shows: followUpShows,
                            formatter: formatter,
                            now: now,
                            onOpenShowLibrary: onOpenShowLibrary,
                            onSetCurrent: onSetCurrentShow,
                            onDetailVisibilityChange: onDetailVisibilityChange
                        )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 25)
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                    } else if attachedCandidateShows.count > 1 {
                        CurrentShowLibraryEntryTile(
                            totalShowCount: attachedCandidateShows.count,
                            onOpenShowLibrary: onOpenShowLibrary
                        )
                        .padding(.horizontal, contentInset)
                        .padding(.top, 25)
                        .opacity(homeArrivalFlags.hasArrivedActions ? 1 : 0)
                    }
                    Color.clear.frame(height: 1).id("home-bottom")
                }
                .padding(.bottom, BSLayout.tabBarContentInset)
                .frame(maxWidth: .infinity)
                #if DEBUG
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--scroll-to-live-section") {
                        try? await Task.sleep(for: .milliseconds(1200))
                        withAnimation(.easeInOut(duration: 0.4)) {
                            scrollProxy.scrollTo("live-section", anchor: .top)
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--scroll-to-bottom") {
                        try? await Task.sleep(for: .milliseconds(1500))
                        scrollProxy.scrollTo("home-bottom", anchor: .bottom)
                    }
                }
                #endif
                }
            }
            .modifier(HomeHeaderScrollObserver(isOverContent: $isHeaderOverContent))

            if isHeaderOverContent {
                // Content scrolling under the header blurs away instead of showing through the title.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.55))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 150)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            CurrentShowHomeHeader(
                show: show,
                live: liveTimetable == nil ? nil : liveState,
                onOpenSettings: onOpenSettings,
                onAddShow: onAddShow,
                weather: weather,
                onOpenWeather: openWeatherDetail
            )
                .padding(.horizontal, contentInset)
                .padding(.top, BSLayout.pageHeaderTopPadding)
                .zIndex(1)
        }
        .animation(.smooth(duration: 0.6), value: liveState?.phase)
        .task(id: liveTimetable?.id) {
            guard let liveTimetable else { return }
            let names = liveTimetable.orderedDays.flatMap(\.performances).map(\.artistName)
            await avatars.load(artistNames: names, lineup: show.isAttached ? show.artists : [])
        }
    }

    private var embedsRouteInLocation: Bool {
        true
    }

    func openRouteChooser() {
        installedMapApps = ExternalMapApp.installed
        presentedSheet = .mapChooser
    }

    private func resolvedRecommendation(snapshot: HomeHeroSnapshot) -> RecommendedFeature? {
        let todayKey = FeatureRecommendationDay.key(for: snapshot.now)
        guard let slot = CurrentShowCardRecommendation.slot(
            timeState: snapshot.timeState,
            hasConfirmedEnd: show.endedAt != nil
        ) else {
            return nil
        }
        let facts = FeatureUsageFacts(hasInstalledWidget: hasInstalledWidget, isICloudAvailable: isICloudAvailable)
        let ledger = FeatureRecommendationLedger.snapshot(
            shows: attachedCandidateShows,
            records: recommendationRecords,
            facts: facts,
            now: snapshot.now
        )
        let hasFutureShow = FeatureRecommendationLedger.nextFutureShow(
            excluding: show.id,
            in: attachedCandidateShows,
            now: snapshot.now
        ) != nil
        let todayNotificationFeature = notificationRecords.first {
            $0.showID == show.id && $0.feature != nil
                && FeatureRecommendationDay.key(for: $0.fireDate) == todayKey
        }?.feature
        return CurrentShowCardRecommendation.resolve(
            chain: slot.chain(
                isFestival: ShowFlavor.inferred(from: show) == .festival,
                hasFutureShow: hasFutureShow
            ),
            context: ledger.context(for: show.id),
            todayKey: todayKey,
            todayNotificationFeature: todayNotificationFeature
        )
    }

    private func presentedSheetDidDismiss() {
        reconcileNotificationsAfterFeatureUse()
        if let date = pendingConfirmedEndDate,
           let intent = pendingEndIntent {
            pendingConfirmedEndDate = nil
            pendingEndIntent = nil
            isPresentationVisibilityLatched = true
            Task { @MainActor in
                let didConfirm = await onConfirmEnd(date)
                guard didConfirm else {
                    releasePresentationLatchIfPossible()
                    return
                }
                switch intent {
                case .justEnded:
                    try? await Task.sleep(for: .milliseconds(700))
                    ceremonyLightsOutShowID = show.id
                case .backfill:
                    ceremonySheetShowID = show.id
                }
            }
            return
        }

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

    private func openMapApp(_ app: ExternalMapApp) {
        guard let query = routeQuery,
              let url = app.openURL(for: query) else { return }
        openURL(url)
    }

    private var companionHistory: [Show] {
        CompanionSharedHistory.shows(
            matching: show,
            from: attachedCandidateShows
        )
    }

}
