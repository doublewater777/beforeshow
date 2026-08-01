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
            AddShowCoordinatorSheet {
                presentAddShowSuccess()
            }
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
            if ProcessInfo.processInfo.arguments.contains("--open-add-show-manual") {
                hasCompletedOnboarding = true
                isShowingFirstShowAdd = true
            }
        }
        #endif
    }

    @Query(sort: \Show.date) private var shows: [Show]

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

            MyShowsListView()
                .opacity(selectedTab == .myShows ? 1 : 0)
                .allowsHitTesting(selectedTab == .myShows)
                .accessibilityHidden(selectedTab != .myShows)

            HomeFloatingTabBar(selectedTab: $selectedTab)
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
                        onConfirmEnd: { endDate in
                            confirmEnd(show, at: endDate)
                        }
                    )
                } else {
                    CurrentShowEmptyStateView(
                        onAddShow: { isShowingAddShowCoordinator = true },
                        onOpenSettings: { isShowingSettings = true }
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
        guard date >= CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current),
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
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .font(.system(size: 12.5, weight: .medium))
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
    var onConfirmEnd: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isShowingEndConfirmation = false
    @State private var isShowingTicket = false

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

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
                showStart: CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current),
                onConfirm: { date in
                    isShowingEndConfirmation = false
                    onConfirmEnd(date)
                },
                onCancel: { isShowingEndConfirmation = false }
            )
        }
        .sheet(isPresented: $isShowingTicket) {
            CurrentShowTicketSheet(
                showName: show.name,
                seatSection: show.seatSection,
                onDismiss: { isShowingTicket = false }
            )
        }
    }

    @ViewBuilder
    private func homeContent(geometry: GeometryProxy, now: Date) -> some View {
        let timeState = CurrentShowTimeState(show: show, now: now)
        let phase = HomeShowPhase(timeState: timeState, now: now)
        let followUpShows = CurrentShowFollowUpPolicy.laterShows(
            from: candidateShows,
            excluding: show.id,
            now: now
        )
        let canRecordEnd = show.endedAt == nil
            && (phase == .live || timeState.kind == .postShow || timeState.kind == .ended)
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

                heroStage(phase: phase, timeState: timeState, coverWidth: coverWidth)
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

    // MARK: Hero（整张海报进入详情，不叠加更多按钮）

    private func heroStage(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        coverWidth: CGFloat
    ) -> some View {
        let coverHeight = coverWidth * 4.0 / 3.0
        return NavigationLink {
            ShowDetailView(show: show)
        } label: {
            heroVisual(phase: phase, timeState: timeState, width: coverWidth, height: coverHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("现场封面，\(show.name)，点按进入详情")
        .accessibilityAddTraits(.isButton)
        .frame(width: coverWidth, height: coverHeight)
    }

    private func heroVisual(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ShowCoverImageView(
            urlString: show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            alignment: .center,
            enforcesAspectRatio: false,
            cornerRadius: 26
        )
        .frame(width: width, height: height)
        .saturation(phase == .inactive ? 0.35 : (phase == .ended ? 0.72 : 1.0))
        .brightness(phase == .inactive ? -0.18 : (phase == .ended ? -0.05 : 0))
        .overlay {
            heroScrim
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .overlay {
            heroGlow(phase: phase, width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .overlay(alignment: .bottomLeading) {
            heroMeta(phase: phase, timeState: timeState)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        // ShowCoverImageView 先按自身比例布局；外层改成固定 3:4 尺寸后必须再次裁切，
        // 否则图片会越过 352pt 卡片边界，让海报看起来横向错位。
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 15)
    }

    /// V4 hero-scrim:顶部更轻,底部 97% 收进封面下缘,让元信息可读。
    private var heroScrim: some View {
        LinearGradient(
            stops: [
                .init(color: BSColor.Stage.background.opacity(0.18), location: 0.00),
                .init(color: BSColor.Stage.background.opacity(0.06), location: 0.26),
                .init(color: BSColor.Stage.background.opacity(0.10), location: 0.46),
                .init(color: BSColor.Stage.background.opacity(0.44), location: 0.66),
                .init(color: BSColor.Stage.background.opacity(0.86), location: 0.88),
                .init(color: BSColor.Stage.background.opacity(0.97), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// hero-glow:蓝 / 紫两束舞台侧光,screen 混合;live 全开,ended 收半,inactive 几近熄灭。
    private func heroGlow(phase: HomeShowPhase, width: CGFloat, height: CGFloat) -> some View {
        let opacity: Double
        switch phase {
        case .live: opacity = 1.0
        case .pre: opacity = 0.92
        case .ended: opacity = 0.45
        case .inactive: opacity = 0.18
        }
        return ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.30), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.26
                ))
                .frame(width: width * 0.52, height: height * 0.34)
                .position(x: width * 0.16, y: height * 0.70)

            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.prepare.opacity(0.28), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.23
                ))
                .frame(width: width * 0.46, height: height * 0.28)
                .position(x: width * 0.88, y: height * 0.62)
        }
        .blendMode(.screen)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func heroMeta(phase: HomeShowPhase, timeState: CurrentShowTimeState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kickerPill(phase: phase, timeState: timeState)
                .padding(.bottom, 10)

            Text(dateLine(timeState: timeState))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BSColor.Stage.foreground.opacity(0.78))
                .padding(.bottom, 8)

            Text(show.name)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)

            if !locationText.isEmpty {
                Text(locationText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(BSColor.Stage.foreground.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private func kickerPill(phase: HomeShowPhase, timeState: CurrentShowTimeState) -> some View {
        let text = phase == .inactive ? timeState.title : phase.kickerText(city: show.city, timeState: timeState)
        return HStack(spacing: 8) {
            if phase == .live {
                HomeLivePulse(reduceMotion: reduceMotion)
            } else {
                Circle()
                    .fill(kickerDotColor(for: phase))
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
        }
        .foregroundColor(kickerTextColor(for: phase))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(kickerTint(for: phase)))
        )
        .overlay(Capsule().stroke(kickerBorderColor(for: phase), lineWidth: 1))
    }

    private func kickerDotColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.accent
        case .live: return BSColor.Stage.live
        case .ended, .inactive: return BSColor.Stage.dim
        }
    }

    private func kickerTextColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.accent
        case .live: return BSColor.Stage.liveTitle
        case .ended, .inactive: return BSColor.Stage.foreground.opacity(0.72)
        }
    }

    private func kickerTint(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.background.opacity(0.38)
        case .live: return Color(red: 0.31, green: 0.09, blue: 0.13).opacity(0.42)
        case .ended, .inactive: return BSColor.Stage.background.opacity(0.45)
        }
    }

    private func kickerBorderColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.accent.opacity(0.28)
        case .live: return BSColor.Stage.live.opacity(0.42)
        case .ended, .inactive: return Color.white.opacity(0.14)
        }
    }

    /// 设计稿 event-date 行:日期时间 · 约 X 分钟 / 小时(多日「每日 HH:mm」已含区间,不追加时长)。
    private func dateLine(timeState: CurrentShowTimeState) -> String {
        let base = formatter.dateText(for: show)
        let isMultiDayDaily = CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: .current)
        guard !isMultiDayDaily, let start = timeState.effectiveStartTime else {
            return base
        }
        if let end = timeState.effectiveEndTime, end > start {
            let minutes = Int(end.timeIntervalSince(start)) / 60
            let hours = minutes / 60
            let rest = minutes % 60
            let duration: String
            if hours > 0 && rest > 0 {
                duration = "约 \(hours) 小时 \(rest) 分"
            } else if hours > 0 {
                duration = "约 \(hours) 小时"
            } else {
                duration = "约 \(max(1, rest)) 分钟"
            }
            return "\(base) · \(duration)"
        }
        return "\(base) · 约 \(CurrentShowTimeState.defaultDurationHours) 小时"
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
        let values = [show.venueAddress, show.venueName, show.city, show.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private var shareText: String {
        let location = locationText.isEmpty ? "" : " · \(locationText)"
        return "一起去 \(show.name) 吗？\n\(formatter.dateText(for: show))\(location)"
    }

    private func quickActionRow(_ actions: [CurrentShowQuickAction]) -> some View {
        HStack(spacing: 9) {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .ticket:
                    Button { isShowingTicket = true } label: {
                        CurrentShowQuickActionTile(action: action)
                    }
                    .buttonStyle(.plain)
                case .route:
                    Button { openRoute() } label: {
                        CurrentShowQuickActionTile(action: action)
                    }
                    .buttonStyle(.plain)
                case .reminder:
                    Button { openNotificationSettings() } label: {
                        CurrentShowQuickActionTile(action: action)
                    }
                    .buttonStyle(.plain)
                case .companion:
                    ShareLink(item: shareText) {
                        CurrentShowQuickActionTile(action: action)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openRoute() {
        guard let routeQuery else { return }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: routeQuery)]
        if let url = components?.url {
            openURL(url)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }
}

enum CurrentShowFollowUpPolicy {
    static func laterShows(
        from shows: [Show],
        excluding currentShowID: UUID?,
        now: Date,
        calendar: Calendar = .current
    ) -> [Show] {
        shows
            .filter { show in
                guard show.id != currentShowID,
                      show.changeStatus == .scheduled,
                      show.endedAt == nil else { return false }
                let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
                return start > now
            }
            .sorted {
                CurrentShowTimeState.effectiveStartTime(for: $0, calendar: calendar)
                    < CurrentShowTimeState.effectiveStartTime(for: $1, calendar: calendar)
            }
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
    case ticket
    case route
    case reminder
    case companion

    var title: String {
        switch self {
        case .ticket: return "票夹"
        case .route: return "路线"
        case .reminder: return "提醒"
        case .companion: return "同行"
        }
    }

    var iconName: String {
        switch self {
        case .ticket: return "ticket"
        case .route: return "map"
        case .reminder: return "bell"
        case .companion: return "person.2"
        }
    }

    /// 当前现场的管理入口保持稳定，避免用户因演出阶段变化而找不到功能。
    static let visibleActions: [Self] = [.ticket, .route, .reminder, .companion]
}

private struct CurrentShowQuickActionTile: View {
    let action: CurrentShowQuickAction

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: action.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(BSColor.Stage.accent)
            Text(action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action.title)
    }
}

private struct CurrentShowTicketSheet: View {
    let showName: String
    let seatSection: String?
    let onDismiss: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(300)) {
            Image(systemName: "ticket")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 56, height: 56)
                .background(BSColor.Stage.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 7) {
                Text("票夹")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(showName)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let seatSection, !seatSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(seatSection)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .padding(.top, 5)
                }
            }

            Button("完成", action: onDismiss)
                .buttonStyle(BSPrimaryButtonStyle())
        }
    }
}

private struct CurrentShowEndConfirmationSheet: View {
    private enum Step { case choice, earlier }

    let showName: String
    let showStart: Date
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var step: Step = .choice
    @State private var selectedEnd: Date

    init(showName: String, showStart: Date, onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.showName = showName
        self.showStart = showStart
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let suggested = min(Date(), showStart.addingTimeInterval(3 * 3_600))
        _selectedEnd = State(initialValue: max(showStart, suggested))
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
            if step == .choice {
                choice
            } else {
                earlierTime
            }
        }
        .interactiveDismissDisabled(false)
    }

    private var choice: some View {
        VStack(spacing: BSSpacing.lg) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(BSColor.Stage.liveTitle)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.live.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("确认已经散场？")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text("记录散场时间，并计入现场记录。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }

            HStack(spacing: 9) {
                Button("早就结束") { step = .earlier }
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("刚刚结束") { onConfirm(Date()) }
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.liveTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BSColor.Stage.live.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Stage.live.opacity(0.34), lineWidth: 1)
                    )
            }

            Button("还没结束", action: onCancel)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(minHeight: BSLayout.minTouchTarget)
        }
    }

    private var earlierTime: some View {
        VStack(spacing: BSSpacing.lg) {
            VStack(spacing: BSSpacing.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 56, height: 56)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("补记散场时间")
                    .font(.system(size: 21, weight: .semibold))
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
                        selection: $selectedEnd,
                        in: showStart...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "散场时间",
                        selection: $selectedEnd,
                        in: showStart...Date(),
                        displayedComponents: .hourAndMinute
                    )
                }
                .tint(BSColor.Stage.accent)
            }

            HStack {
                Text("现场时长")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                Spacer()
                Text(durationText)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
            }

            HStack(spacing: 9) {
                Button("返回") { step = .choice }
                    .buttonStyle(BSSecondaryButtonStyle())
                Button("确认这个时间") { onConfirm(selectedEnd) }
                    .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private var durationText: String {
        let minutes = max(0, Int(selectedEnd.timeIntervalSince(showStart) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) 分" }
        if rest == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(rest) 分"
    }
}

// MARK: - Empty State

private struct CurrentShowEmptyStateView: View {
    let onAddShow: () -> Void
    let onOpenSettings: () -> Void

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

// MARK: - Splash

private struct SplashView: View {
    let onFinish: () -> Void

    @State private var backgroundOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var englishNameOpacity = 0.0
    @State private var sloganOpacity = 0.0
    @State private var wholeOpacity = 1.0
    @State private var canAccelerate = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                Image("splash_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .opacity(backgroundOpacity)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("开场前")
                    .font(.system(size: 52, weight: .light))
                    .tracking(6)
                    .foregroundStyle(brandGradient)
                    .opacity(titleOpacity)
                    .accessibilityAddTraits(.isHeader)

                Text("BeforeShow")
                    .font(.system(size: 16, weight: .light))
                    .tracking(8)
                    .foregroundStyle(brandGradient.opacity(0.7))
                    .opacity(englishNameOpacity)

                Text("灯亮之前，先进入状态")
                    .font(.system(size: 14, weight: .light))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(sloganOpacity)
                    .padding(.top, 34)

                Spacer()
                    .frame(height: 142)
            }
            .padding(.horizontal, 28)
        }
        .opacity(wholeOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAccelerate else { return }
            finish()
        }
        .onAppear(perform: startAnimation)
        .accessibilityElement(children: .combine)
    }

    private func startAnimation() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.8)) {
                backgroundOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut(duration: 0.4)) {
                titleOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                englishNameOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                sloganOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.2))
            canAccelerate = true

            try? await Task.sleep(for: .seconds(0.4))
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: 0.32)) {
            wholeOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.32))
            onFinish()
        }
    }
}

private var brandGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0),
            Color(red: 0.70, green: 0.53, blue: 1.0),
            Color(red: 1.0, green: 0.70, blue: 0.28)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
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
