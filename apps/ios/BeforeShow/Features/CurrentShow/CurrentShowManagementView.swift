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
