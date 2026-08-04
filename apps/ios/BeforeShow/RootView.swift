import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var selectedTab: BeforeShowTab = .current
    @State private var isShowingFirstShowAdd = false
    @State private var addShowToast: BSToastPayload?
    @State private var isTabBarHidden = false

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding && shows.isEmpty {
                OnboardingPlaceholderView(
                    onStartFirstShow: { isShowingFirstShowAdd = true },
                    onSkip: { hasCompletedOnboarding = true }
                )
                .opacity(hasFinishedSplash ? 1 : 0)
            } else {
                mainTabView
                    .opacity(hasFinishedSplash ? 1 : 0)
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
        .bsToastOverlay(addShowToast, bottomPadding: 90)
        .sheet(isPresented: $isShowingFirstShowAdd, onDismiss: {
            hasCompletedOnboarding = true
        }) {
            AddShowCoordinatorSheet(
                initialSheet: Self.debugOpenAddShowManual ? .manual : nil
            ) {
                presentAddShowSuccess()
            }
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
            FootprintDebugSeeder.seedIfRequested(in: modelContext)
            if ProcessInfo.processInfo.arguments.contains("--open-footprints") {
                hasCompletedOnboarding = true
                selectedTab = .footprints
            }
            if Self.debugOpenAddShowManual {
                hasCompletedOnboarding = true
                isShowingFirstShowAdd = true
            }
        }
        #endif
    }

    @Query(sort: \Show.date) private var shows: [Show]

    /// DEBUG launch arg for UI tests: open first-show sheet already on 手动填写.
    /// Scoped to that sheet only — 足迹补录 / 其它添加入口仍走三选一。
    private static var debugOpenAddShowManual: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--open-add-show-manual")
        #else
        false
        #endif
    }

    private func presentAddShowSuccess() {
        let payload = BSToastPayload(tone: .success, message: "已放入当前现场")
        addShowToast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if addShowToast == payload {
                addShowToast = nil
            }
        }
    }

    /// V4:系统 TabView 换成浮动玻璃 Tab,内容可滚动到 Tab 上方透出,而不是被贴边条带切断。
    /// 两个 Tab root 常驻挂载(透明度切换),避免切换时丢掉导航栈、sheet、滚动等本地状态。
    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            CurrentShowHomeView()
                .opacity(selectedTab == .current ? 1 : 0)
                .allowsHitTesting(selectedTab == .current)
                .accessibilityHidden(selectedTab != .current)

            FootprintsView(onArchiveVisibilityChange: { isTabBarHidden = $0 })
                .opacity(selectedTab == .footprints ? 1 : 0)
                .allowsHitTesting(selectedTab == .footprints)
                .accessibilityHidden(selectedTab != .footprints)

            if !isTabBarHidden {
                HomeFloatingTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Onboarding Placeholder

private struct OnboardingPlaceholderView: View {
    let onStartFirstShow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: BSSpacing.lg) {
                Spacer()

                Text("开场前")
                    .font(.system(size: 48, weight: .light))
                    .tracking(6)
                    .bsGradientText()

                Text("把要去的现场放进来，\n慢慢靠近那一场。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onStartFirstShow) {
                    Text("添加第一场现场")
                        .font(BSFont.caption)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                }
                .padding(.horizontal, 48)

                Button("先逛逛", action: onSkip)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)

                Spacer()
            }
        }
    }
}

// MARK: - Current Show Home

private struct CurrentShowHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingAddShowCoordinator = false
    @State private var toast: BSToastPayload?
    @State private var isShowingSettings = false
    @State private var isShowingShowLibrary = false

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
            // AmbientBackground 的理想宽度可能超过屏幕（见 homeContent 的 UIScreen 封顶注释），
            // 这里一并封顶，避免内容被顶出屏幕。
            ZStack {
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)

                if let show = currentShow {
                    CurrentShowManagementSection(
                        show: show,
                        formatter: formatter,
                        candidateShows: shows,
                        onAddShow: { isShowingAddShowCoordinator = true },
                        onOpenSettings: { isShowingSettings = true },
                        onOpenShowLibrary: { isShowingShowLibrary = true },
                        onConfirmEnd: { endDate in
                            confirmEnd(show, at: endDate)
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
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet {
                    presentAddShowSuccess()
                }
            }
            .task(id: widgetSyncFingerprint) {
                WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    WidgetDataSync.sync(shows: shows, manualSelection: selections.first)
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $isShowingShowLibrary) {
                CurrentShowLibraryManagementView()
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("--open-settings") {
                    isShowingSettings = true
                }
            }
            #endif
        }
    }

    private func presentAddShowSuccess() {
        let payload = BSToastPayload(tone: .success, message: "已放入当前现场")
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }

    private func confirmEnd(_ show: Show, at date: Date) {
        guard date >= CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: .current),
              date <= Date() else {
            presentToast(.failure, message: "散场时间需要在开场后、当前时间前")
            return
        }

        show.markEnded(at: date)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: "散场时间没有保存，请重试")
            return
        }

        presentToast(.success, message: "已落幕，散场时间已计入现场记录")
        Task { @MainActor in
            _ = await LocalNotificationCenter.shared.applyFocusChange(to: show, in: modelContext)
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

// MARK: - Floating Tab Bar

/// V4:浮动玻璃 Tab。玻璃态透出下方内容;各页用 tabBarContentInset 预留滚动空间。
private struct HomeFloatingTabBar: View {
    @Binding var selectedTab: BeforeShowTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BeforeShowTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                        .foregroundColor(selectedTab == tab ? BSColor.Stage.accent : BSColor.Stage.muted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(
                                selectedTab == tab ? BSColor.Stage.accent.opacity(0.14) : .clear
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(BSColor.Stage.surface.opacity(0.52)))
        }
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 17, y: 7)
        .padding(.bottom, 22)
    }
}

// MARK: - Current Show Management

/// 当前现场从页头、海报到阶段快捷功能的可复用管理区。
/// 只消费真实 `Show` 与 `CurrentShowTimeState`，不负责下一场、列表或历史内容。
struct CurrentShowManagementSection: View {
    let show: Show
    let formatter: ShowDisplayFormatter
    let candidateShows: [Show]
    var onAddShow: () -> Void
    var onOpenSettings: () -> Void
    var onOpenShowLibrary: () -> Void
    var onConfirmEnd: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
    @Query private var memoryFragments: [MemoryFragment]
    @Query private var showAssets: [ShowAsset]
    @State private var isShowingEndConfirmation = false
    @State private var isShowingMapChooser = false
    @State private var isShowingCompanion = false
    @State private var companionErrorMessage: String?

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    private var currentTimeState: CurrentShowTimeState { CurrentShowTimeState(show: show, now: Date()) }
    private var currentPhase: HomeShowPhase { HomeShowPhase(timeState: currentTimeState) }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.everyMinute) { context in
                homeContent(geometry: geometry, now: context.date)
            }
        }
        .id(show.updatedAt)
        .sheet(isPresented: $isShowingEndConfirmation) {
            CurrentShowEndConfirmationSheet(
                showName: show.name,
                showStart: CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: .current),
                suggestedEnd: currentTimeState.endBoundary ?? CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current),
                allowsJustEnded: currentPhase == .live,
                onConfirm: { date in
                    isShowingEndConfirmation = false
                    onConfirmEnd(date)
                },
                onCancel: { isShowingEndConfirmation = false }
            )
        }
        .sheet(isPresented: $isShowingMapChooser) {
            CurrentShowMapChooserSheet(
                destinationQuery: routeQuery,
                destinationLabel: mapDestinationLabel,
                onSelect: { app in
                    openMapApp(app)
                    isShowingMapChooser = false
                },
                onCancel: { isShowingMapChooser = false }
            )
        }
        .sheet(isPresented: $isShowingCompanion) {
            CurrentShowCompanionSheet(
                show: show,
                sharedHistory: companionHistory,
                isEnded: currentPhase == .ended,
                coordinator: companionCoordinator,
                onDismiss: { isShowingCompanion = false }
            )
        }
        .alert(
            "同行",
            isPresented: Binding(
                get: { companionErrorMessage != nil },
                set: { if !$0 { companionErrorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { companionErrorMessage = nil }
        } message: {
            Text(companionErrorMessage ?? "")
        }
        .task(id: show.companionCloudRecordName) {
            await companionCoordinator.refreshCompanion(for: show, in: modelContext)
            if let accepted = companionCoordinator.consumePendingAcceptMessage() {
                companionErrorMessage = accepted
            } else if let error = companionCoordinator.consumeLastErrorMessage() {
                companionErrorMessage = error
            }
        }
    }

    @ViewBuilder
    private func homeContent(geometry: GeometryProxy, now: Date) -> some View {
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
            now: now
        )
        // GeometryReader 受同层 AmbientBackground 影响可能宽于屏幕,
        // 与旧版 HomeLayoutMetrics 一样用 UIScreen 宽度封顶(内容列居中回落到真实视口)。
        let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
        // V4 封面为居中立起的 3:4 对象(原型 352pt 宽,窄机退回屏宽 - 40)。
        let coverWidth = min(352, max(0, viewportWidth - 40))

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                managementHeader
                    .padding(.horizontal, contentInset)
                    .padding(.top, 4)

                HomeHeroStage(
                    show: show,
                    snapshot: snapshot,
                    coverWidth: coverWidth,
                    reduceMotion: reduceMotion
                )
                    .padding(.top, 18)

                HomeCountdownLockup(
                    show: show,
                    onEndShow: canRecordEnd
                        ? { isShowingEndConfirmation = true }
                        : nil
                )
                    .padding(.horizontal, 21)
                    .padding(.top, 20)

                quickActionRow(CurrentShowQuickAction.visibleActions)
                    .padding(.horizontal, contentInset)
                    .padding(.top, 17)

                if !followUpShows.isEmpty {
                    CurrentShowFollowUpSummary(
                        shows: followUpShows,
                        formatter: formatter,
                        now: now
                    )
                    .padding(.horizontal, contentInset)
                    .padding(.top, 25)
                }
            }
            .padding(.bottom, BSLayout.tabBarContentInset)
            .frame(width: viewportWidth)
            .frame(width: geometry.size.width, alignment: .center)
            .frame(minHeight: geometry.size.height, alignment: .top)
        }
    }

    private var managementHeader: some View {
        HStack {
            Text("当前")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                headerButton(icon: "gearshape", label: "设置", action: onOpenSettings)
                headerButton(icon: "list.bullet.rectangle", label: "全部现场", action: onOpenShowLibrary)
                headerButton(icon: "plus", label: "添加现场", action: onAddShow)
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

    /// 弹窗副标题：优先场馆名，其次城市 / 演出名。
    private var mapDestinationLabel: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let venue, !venue.isEmpty { return venue }
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let city, !city.isEmpty { return city }
        return show.name
    }

    private func quickActionRow(_ actions: [CurrentShowQuickAction]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(actions, id: \.self) { action in
                    switch action {
                    case .route:
                        Button { isShowingMapChooser = true } label: {
                            CurrentShowQuickActionTile(action: action)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 86)
                    case .companion:
                        Button { isShowingCompanion = true } label: {
                            CurrentShowQuickActionTile(
                                action: action,
                                companion: CompanionQuickActionPresentation(
                                    status: show.companionStatus,
                                    companionName: show.companionName,
                                    isEnded: currentPhase == .ended
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: 86)
                    case .ticket, .timetable:
                        Group {
                            let kind: ShowAssetKind = action == .ticket ? .ticket : .timetable
                            NavigationLink {
                                ShowAssetEntryView(showID: show.id, showName: show.name, kind: kind)
                            } label: {
                                CurrentShowQuickActionTile(
                                    action: action,
                                    subtitle: assetSubtitle(for: kind)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 86)
                    case .memoryFragments:
                        NavigationLink {
                            MemoryFragmentsView(showID: show.id, showName: show.name)
                        } label: {
                            CurrentShowQuickActionTile(
                                action: action,
                                subtitle: memoryFragmentCount == 0 ? "记录这一刻" : "\(memoryFragmentCount) 条"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: 86)
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private var memoryFragmentCount: Int {
        memoryFragments.lazy.filter { $0.showID == show.id }.count
    }

    private func assetSubtitle(for kind: ShowAssetKind) -> String {
        let saved = showAssets.contains { $0.showID == show.id && $0.kind == kind }
        return saved ? kind.savedSubtitle : kind.emptySubtitle
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

enum CompanionSharedHistory {
    /// Aggregate only when a stable non-empty companion name exists.
    /// Unnamed confirmed companions must not merge across unrelated shows.
    static func shows(matching show: Show, from candidates: [Show]) -> [Show] {
        let normalizedName = show.companionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedName, !normalizedName.isEmpty else {
            if show.companionStatus == .confirmed, show.endedAt != nil {
                return [show]
            }
            return []
        }

        return candidates
            .filter { candidate in
                candidate.companionStatus == .confirmed
                    && candidate.endedAt != nil
                    && candidate.companionName?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName
            }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }
}

private struct CurrentShowFollowUpSummary: View {
    let shows: [Show]
    let formatter: ShowDisplayFormatter
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("之后还有")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .foregroundColor(BSColor.Stage.muted)
                Text("\(shows.count) 场")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
                Spacer()
            }

            ForEach(shows.prefix(2)) { show in
                NavigationLink {
                    ShowDetailView(show: show)
                } label: {
                    followUpRow(show)
                }
                .buttonStyle(.plain)
            }

            if shows.count > 2 {
                NavigationLink {
                    CurrentShowLibraryManagementView()
                } label: {
                    HStack(spacing: 8) {
                        Text("查看我的现场 · \(shows.count) 场")
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
        if seconds >= 86_400 { return "\(seconds / 86_400) 天后" }
        if seconds >= 3_600 { return "\(seconds / 3_600) 小时后" }
        return "\(max(1, seconds / 60)) 分钟后"
    }
}

enum CurrentShowQuickAction: Hashable {
    case route
    case companion
    case ticket
    case timetable
    case memoryFragments

    var title: String {
        switch self {
        case .route: return "路线"
        case .companion: return "同行"
        case .ticket: return "票根"
        case .timetable: return "时刻表"
        case .memoryFragments: return "记忆碎片"
        }
    }

    var iconName: String {
        switch self {
        case .route: return "map"
        case .companion: return "person.2"
        case .ticket: return "ticket"
        case .timetable: return "list.bullet.rectangle"
        case .memoryFragments: return "photo.on.rectangle.angled"
        }
    }

    /// 当前现场的管理入口保持稳定，避免用户因演出阶段变化而找不到功能。
    static let visibleActions: [Self] = [.route, .companion, .ticket, .timetable, .memoryFragments]
}

struct CompanionQuickActionPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let companionName: String?
    let showsPendingIndicator: Bool
    let showsAvatars: Bool

    init(status: ShowCompanionStatus, companionName: String?, isEnded: Bool) {
        let name = companionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.flatMap { $0.isEmpty ? nil : $0 }
        self.companionName = normalizedName
        switch status {
        case .none:
            title = "同行"
            accessibilityLabel = "同行，邀请一位朋友"
            showsPendingIndicator = false
            showsAvatars = false
        case .pending:
            title = "待确认"
            accessibilityLabel = normalizedName.map { "同行，等待\($0)确认" } ?? "同行，待确认"
            showsPendingIndicator = true
            showsAvatars = false
        case .confirmed:
            let displayName = normalizedName ?? "同行者"
            title = isEnded ? "共同足迹" : "与\(displayName)"
            accessibilityLabel = isEnded
                ? (normalizedName.map { "同行，与\($0)的共同足迹" } ?? "同行，共同足迹")
                : "同行，与\(displayName)已确认"
            showsPendingIndicator = false
            showsAvatars = true
        case .canceled:
            title = "重新邀请"
            accessibilityLabel = normalizedName.map { "同行，重新邀请\($0)" } ?? "同行，重新邀请"
            showsPendingIndicator = false
            showsAvatars = false
        }
    }
}

private struct CurrentShowQuickActionTile: View {
    let action: CurrentShowQuickAction
    var companion: CompanionQuickActionPresentation?
    var subtitle: String?

    var body: some View {
        VStack(spacing: 7) {
            if let companion, companion.showsAvatars {
                CompanionAvatarStack(name: companion.companionName ?? "同行者")
            } else {
                Image(systemName: action.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            }
            Text(companion?.title ?? action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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
    let name: String

    var body: some View {
        HStack(spacing: -8) {
            avatar("我", colors: [BSColor.Stage.accent, BSColor.Stage.glowBlue])
            avatar(initial, colors: [BSColor.Accent.violet, BSColor.Stage.accent])
        }
        .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "共同足迹" ? "友" : String(trimmed.prefix(1))
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

private struct CurrentShowCompanionSheet: View {
    let show: Show
    let sharedHistory: [Show]
    let isEnded: Bool
    let coordinator: CompanionSharingCoordinator
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var companionName: String
    @State private var isShowingHistory = false
    @State private var isPreparingInvite = false
    @State private var isRefreshing = false
    @State private var isCanceling = false
    @State private var cloudShareData: IdentifiableShareData?
    @State private var errorMessage: String?

    init(
        show: Show,
        sharedHistory: [Show],
        isEnded: Bool,
        coordinator: CompanionSharingCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.show = show
        self.sharedHistory = sharedHistory
        self.isEnded = isEnded
        self.coordinator = coordinator
        self.onDismiss = onDismiss
        _companionName = State(initialValue: show.companionName ?? "")
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
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

                    Button("完成", action: onDismiss)
                        .buttonStyle(BSSecondaryButtonStyle())
                }
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $cloudShareData) { item in
            CloudSharingPresenter(
                shareData: item.data,
                containerIdentifier: CloudKitCompanionSharingService.defaultContainerIdentifier,
                show: show,
                coordinator: coordinator,
                onFinished: {
                    cloudShareData = nil
                    if let error = coordinator.consumeLastErrorMessage() {
                        errorMessage = error
                    }
                }
            )
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
            await coordinator.refreshCompanion(for: show, in: modelContext)
        }
    }

    private func invitationContent(isRetry: Bool) -> some View {
        VStack(spacing: BSSpacing.md) {
            sheetHeader(
                icon: "person.2",
                title: isRetry ? "邀请未接受" : "邀请同行",
                subtitle: isRetry
                    ? "可以通过 iCloud 重新发送邀请，对方点开链接后双方都会确认。"
                    : "通过 iCloud 邀请一位朋友。对方接受后，双方同步为已确认同行。"
            )

            TextField("同行者名字（可选）", text: $companionName)
                .textInputAutocapitalization(.words)
                .bsInputField()

            Button {
                Task { await sendInvitation(isRetry: isRetry) }
            } label: {
                if isPreparingInvite {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(isRetry ? "重新邀请" : "分享邀请", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isPreparingInvite)
        }
    }

    private var pendingContent: some View {
        VStack(spacing: BSSpacing.md) {
            sheetHeader(
                icon: "hourglass",
                title: "等待\(displayName)确认",
                subtitle: "已通过 iCloud 发出邀请。对方点开链接并接受后，这里会自动变成已确认。"
            )

            Button {
                Task { await resendInvitation() }
            } label: {
                Label("再次发送", systemImage: "paperplane")
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
                    Label("刷新状态", systemImage: "arrow.clockwise")
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
                sheetHeader(
                    icon: "person.2.fill",
                    title: "共同足迹",
                    subtitle: "这场现场已经收进你们共同的记录。"
                )

                sharedMemoryCard

                ShareLink(item: sharedFootprintShareText) {
                    Label("分享共同足迹", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        } else {
            VStack(spacing: BSSpacing.md) {
                sheetHeader(
                    icon: "person.2.fill",
                    title: "与\(displayName)同行",
                    subtitle: "这场现场已确认同行。"
                )

                companionPair

                Text("你们共同看过 \(sharedHistory.count) 场现场")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)

                if isShowingHistory {
                    historyList
                } else {
                    Button("查看共同足迹") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingHistory = true
                        }
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                }

                destructiveButton("取消同行") {
                    Task { await cancelInvitation() }
                }
                .disabled(isCanceling)
            }
        }
    }

    private var companionPair: some View {
        HStack(spacing: BSSpacing.md) {
            person(name: "你", initial: "我")

            Rectangle()
                .fill(LinearGradient(colors: [.clear, BSColor.Stage.accent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(maxWidth: 70, maxHeight: 1)

            person(name: displayName, initial: companionInitial)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSSpacing.sm)
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
            Text("我们一起看的\n第 \(max(1, sharedHistory.count)) 场现场")
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

    private func sheetHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 54, height: 54)
                .background(BSColor.Stage.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(subtitle)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
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

    private var displayName: String {
        let trimmed = (show.companionName ?? companionName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "同行者" : trimmed
    }

    private var companionInitial: String {
        String(displayName.prefix(1))
    }

    private var sharedFootprintShareText: String {
        "我和\(displayName)一起看了 \(show.name)。\n这是我们共同记录的第 \(max(1, sharedHistory.count)) 场现场。"
    }

    @MainActor
    private func sendInvitation(isRetry: Bool) async {
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        if isRetry, show.companionShareLocator != nil {
            errorMessage = "请先完成取消同步，再重新邀请"
            return
        }
        do {
            let prepared = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: companionName,
                ownerDisplayName: nil,
                in: modelContext
            )
            cloudShareData = IdentifiableShareData(data: prepared.shareSystemFields)
        } catch {
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func resendInvitation() async {
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        do {
            let data = try await coordinator.shareSystemFieldsForResend(show: show)
            cloudShareData = IdentifiableShareData(data: data)
        } catch let error as CompanionSharingError where error == .sessionNotFound {
            // Only recreate when CloudKit positively reports the share is gone.
            await sendInvitation(isRetry: true)
        } catch {
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
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

/// Wrapper so CloudKit share blobs can drive `fullScreenCover(item:)`.
private struct IdentifiableShareData: Identifiable {
    let id = UUID()
    let data: Data
}

private struct CurrentShowMapChooserSheet: View {
    let destinationQuery: String?
    let destinationLabel: String
    let onSelect: (ExternalMapApp) -> Void
    let onCancel: () -> Void

    /// 仅展示本机已安装的地图；在 `onAppear` 用 `canOpenURL` 刷新。
    @State private var installedApps: [ExternalMapApp] = ExternalMapApp.installed

    private var hasDestination: Bool {
        guard let destinationQuery else { return false }
        return !destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sheetHeight: CGFloat {
        if !hasDestination { return 280 }
        if installedApps.isEmpty { return 300 }
        // 标题区 + 行高 + 取消 + 内边距
        return 200 + CGFloat(installedApps.count) * 62 + 56
    }

    var body: some View {
        BSDrawerSheet(detent: .height(sheetHeight)) {
            VStack(spacing: BSSpacing.md) {
                Image(systemName: "map")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 7) {
                    Text("在地图中打开")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(hasDestination ? destinationLabel : "还没有可打开的位置")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }

            if hasDestination {
                if installedApps.isEmpty {
                    Text("没有检测到可用的地图 App。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 9) {
                        ForEach(installedApps) { app in
                            Button {
                                onSelect(app)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: app.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.accent)
                                        .frame(width: 28)
                                    Text(app.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.foreground)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.dim)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(BSColor.Stage.surface.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(app.title)
                        }
                    }
                }
            } else {
                Text("补充场馆或地址后，就能跳到地图 App。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button("取消", action: onCancel)
                .buttonStyle(BSSecondaryButtonStyle())
        }
        .onAppear {
            installedApps = ExternalMapApp.installed
        }
    }
}

private struct CurrentShowEmptyStateView: View {
    let onAddShow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenShowLibrary: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.system(size: 34, weight: .light))
                .bsGradientText()
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )

            Text("先添加一场现场")
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("把要去的音乐现场放进来，\n慢慢靠近那一场。")
                .font(BSFont.body)
                .foregroundColor(BSColor.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onAddShow) {
                Text("添加现场")
                    .font(BSFont.caption)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
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
                Text("当前")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                HStack(spacing: 8) {
                    emptyHeaderButton(icon: "gearshape", label: "设置", action: onOpenSettings)
                    emptyHeaderButton(icon: "list.bullet.rectangle", label: "全部现场", action: onOpenShowLibrary)
                    emptyHeaderButton(icon: "plus", label: "添加现场", action: onAddShow)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
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
        if ProcessInfo.processInfo.arguments.contains("--seed-current-management-live") {
            seedCurrentManagementLive(in: modelContext)
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

    private static func seedCurrentManagementLive(in modelContext: ModelContext) {
        let name = "当前现场管理 · Live 验证"
        let now = Date()
        let start = now.addingTimeInterval(-84 * 60)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "台北",
            venueName: "Legacy Taipei",
            venueAddress: "台北市信义区松寿路 20 号",
            artist: "BeforeShow Live",
            seatSection: "摇滚区 A 排",
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
                ShowDraft(name: "后续现场 · 第一场", date: now.addingTimeInterval(5 * 86_400), startTime: now.addingTimeInterval(5 * 86_400), city: "新北", venueName: "Zepp New Taipei", artist: "Future One", source: .manual),
                ShowDraft(name: "后续现场 · 第二场", date: now.addingTimeInterval(18 * 86_400), startTime: now.addingTimeInterval(18 * 86_400), city: "台中", venueName: "Legacy Taichung", artist: "Future Two", source: .manual),
                ShowDraft(name: "后续现场 · 第三场", date: now.addingTimeInterval(42 * 86_400), startTime: now.addingTimeInterval(42 * 86_400), city: "高雄", venueName: "LIVE WAREHOUSE", artist: "Future Three", source: .manual)
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

            let endedDraft = ShowDraft(name: "管理页验证 · 已结束", date: now.addingTimeInterval(-10 * 86_400), startTime: now.addingTimeInterval(-10 * 86_400), city: "台北", venueName: "The Wall", artist: "Past Show", source: .manual)
            if let existing = existingShows.first(where: { $0.name == endedDraft.name }) {
                try existing.apply(endedDraft)
                existing.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
            } else {
                let ended = try endedDraft.makeShow()
                ended.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
                modelContext.insert(ended)
            }

            let canceledDraft = ShowDraft(name: "管理页验证 · 已取消", date: now.addingTimeInterval(28 * 86_400), startTime: now.addingTimeInterval(28 * 86_400), city: "台南", venueName: "漂丿白鹭", artist: "Canceled Show", source: .manual)
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
                artist: "周杰伦",
                coverImageURL: "https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp",
                source: .link
            ),
            ShowDraft(
                name: "绿洲音乐节2.0·湖州吴兴站",
                date: date(2026, 6, 27),
                startTime: time(2026, 6, 27, 14, 0),
                city: "湖州",
                venueName: "吴乐湾音乐广场",
                artist: "刘雨昕, 姚琛, 二手玫瑰, DOUDOU, 椿乐队, 裁缝铺, 麻园诗人, 梅卡德尔, 石岩, 声音碎片, 声音玩具",
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
#endif

#Preview {
    RootView()
}
