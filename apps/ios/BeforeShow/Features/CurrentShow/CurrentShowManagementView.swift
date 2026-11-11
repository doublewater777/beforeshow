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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var presentedSheet: CurrentShowPresentedSheet?
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
    @State var homeRoute: CurrentShowHomeRoute?
    @State var revealedUnlocks: ShowUnlocks?
    @State var unlocksAnimateArrival = false

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    private var currentTimeState: CurrentShowTimeState { CurrentShowTimeState(show: show, now: Date()) }
    var currentPhase: HomeShowPhase { HomeShowPhase(timeState: currentTimeState) }

    private var hasPresentationRequest: Bool {
        presentedSheet != nil
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
                homeContent(
                    now: now,
                    topInset: geometry.safeAreaInsets.top,
                    isWide: BSWideLayout.isWide(width: geometry.size.width, sizeClass: horizontalSizeClass),
                    width: geometry.size.width,
                    liveState: liveState
                )
            }
        }
        .navigationDestination(item: $homeRoute) { route in
            switch route {
            case .editShow:
                ShowDetailView(show: show, startsEditing: true, onDetailVisibilityChange: onDetailVisibilityChange)
            case .recordWall:
                FootprintRecordWallView(archive: FootprintArchiveBuilder.make(shows: attachedCandidateShows))
            case .badgeWall:
                FootprintBadgeWallView(archive: FootprintArchiveBuilder.make(shows: attachedCandidateShows))
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
        .bsSheetOrCover(item: $presentedSheet, isCover: { $0 == .asset(.timetable) }, onDismiss: presentedSheetDidDismiss) { sheet in
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
                CompanionEditorSheet(show: show)
            case .asset(let kind):
                ShowAssetSheet(
                    showID: show.id,
                    showName: show.name,
                    kind: kind,
                    onDetailVisibilityChange: onDetailVisibilityChange
                )
            case .memory:
                MemoryFragmentsSheet(show: show)
            case .memoryCreate:
                MemoryFragmentsSheet(show: show, pendingCreate: .quick)
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
    private func homeContent(now: Date, topInset: CGFloat, isWide: Bool, width: CGFloat, liveState: LiveModeState?) -> some View {
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
        let displayedPrimaryAction: HomeCountdownLockup.PrimaryAction? = liveState == nil
            ? HomeCountdownLockup.primaryAction(
                timeState: timeState,
                now: now,
                hasRecord: timeState.kind == .postShow && unlockedRecord != nil,
                hasFutureShow: FeatureRecommendationLedger.nextFutureShow(
                    excluding: show.id,
                    in: attachedCandidateShows,
                    now: now
                ) != nil
            )
            : nil

        let screens = liveState.flatMap(HomeStageScreens.resolve)
        let hero = HomeStageHero(
            show: show,
            snapshot: snapshot,
            reduceMotion: reduceMotion,
            topExtension: topInset + BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding + 18,
            screens: liveTimetable == nil ? nil : screens,
            livePhase: liveState?.phase,
            timetable: liveTimetable,
            avatars: avatars,
            onOpenTimetable: { presentedSheet = .asset(.timetable) },
            onFocus: { focusedPerformanceID = $0.uuidString }
        )
        let allActions = CurrentShowQuickAction.deduplicated(
            CurrentShowQuickAction.actions(
                for: phase,
                canRecordEnd: canRecordEnd && liveState?.phase != .fullyEnded,
                isPostShowRetention: timeState.kind == .postShow && show.endedAt != nil,
                hasCompletedDispersalCeremony: show.hasCompletedDispersalCeremony
            ),
            primaryAction: displayedPrimaryAction
        )
        let headerSpacer = Color.clear.frame(height: BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding)

        let stageColumn = VStack(spacing: 0) {
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

            Group {
                if let liveState, let timetable = liveTimetable {
                    HomeLiveModeView(show: show, timetable: timetable, state: liveState, avatars: avatars, onEndShow: canRecordEnd ? { presentedSheet = .endConfirmation } : nil) { presentedSheet = .asset(.timetable) }
                } else {
                    HomeCountdownLockup(
                        show: show,
                        snapshot: snapshot,
                        primaryAction: displayedPrimaryAction,
                        isPlaying: isCurrentShowAudioActive(
                            room: ListeningRoomSessionStore.shared.room,
                            action: displayedPrimaryAction
                        ),
                        onPrimaryAction: performPrimaryAction,
                        onOpenRoute: embedsRouteInLocation
                            ? { openRouteChooser() }
                            : nil,
                        unlocks: revealedUnlocks?.showID == show.id ? revealedUnlocks : nil,
                        unlocksAnimateArrival: unlocksAnimateArrival,
                        onOpenRecords: { homeRoute = .recordWall },
                        onOpenBadges: { homeRoute = .badgeWall }
                    )
                    .id("live-section")
                }
            }
            .padding(.horizontal, contentInset)
            // The countdown is printed on the stage lip, over the crowd.
            .padding(.top, liveTimetable == nil ? -46 : 4)
            .opacity(homeArrivalFlags.hasArrivedCountdown ? 1 : 0)
            .offset(y: homeArrivalFlags.hasArrivedCountdown ? 0 : 18)
        }

        let actionsColumn = VStack(spacing: 0) {
            CurrentShowActionModules(show: show, actions: allActions, companion: companionPresentation, now: now, routeIsProminent: phase == .pre, timetableIsLive: liveTimetable != nil, recordPhase: phase, perform: performQuickAction)
                .padding(.horizontal, contentInset)
                .padding(.top, isWide ? 18 : 28)
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

        ZStack(alignment: .top) {
            Group {
                if isWide {
                    // iPad：左栏舞台与倒计时，右栏功能卡，各自滚动。
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                headerSpacer
                                stageColumn
                            }
                            .padding(.bottom, BSLayout.tabBarContentInset)
                        }
                        .frame(width: BSWideLayout.leadingColumnWidth(for: width))

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                headerSpacer
                                actionsColumn
                            }
                            .padding(.bottom, BSLayout.tabBarContentInset)
                            .padding(.trailing, BSSpacing.sm)
                        }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        ScrollViewReader { scrollProxy in
                            LazyVStack(spacing: 0) {
                                headerSpacer
                                stageColumn
                                actionsColumn
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
        .task(id: "\(show.id)|\(timeState.kind == .postShow)|\(isHeroPlaybackActive)") {
            revealUnlocksIfNeeded(isPostShow: timeState.kind == .postShow)
        }
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

        if presentedSheet != nil {
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

    private func isCurrentShowAudioActive(
        room: ListeningRoomCoordinator?,
        action: HomeCountdownLockup.PrimaryAction?
    ) -> Bool {
        guard let room, room.wantsPlayback, let action else { return false }
        return isPlayingCurrentShowContent(action: action, in: room)
    }
}
