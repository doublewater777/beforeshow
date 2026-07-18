import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var selectedTab: BeforeShowTab = .current
    @State private var isShowingFirstShowAdd = false

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
        .sheet(isPresented: $isShowingFirstShowAdd, onDismiss: {
            hasCompletedOnboarding = true
        }) {
            AddShowCoordinatorSheet()
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
        }
        #endif
    }

    @Query(sort: \Show.date) private var shows: [Show]

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            CurrentShowHomeView()
                .tabItem {
                    Label(BeforeShowTab.current.rawValue, systemImage: BeforeShowTab.current.iconName)
                }
                .tag(BeforeShowTab.current)

            MyShowsListView()
                .tabItem {
                    Label(BeforeShowTab.myShows.rawValue, systemImage: BeforeShowTab.myShows.iconName)
                }
                .tag(BeforeShowTab.myShows)

            SettingsView()
                .tabItem {
                    Label(BeforeShowTab.settings.rawValue, systemImage: BeforeShowTab.settings.iconName)
                }
                .tag(BeforeShowTab.settings)
        }
        .tint(.white)
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
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var isShowingAddShowCoordinator = false

    private let session = CurrentShowSession()
    private let formatter = ShowDisplayFormatter()

    private var currentShow: Show? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)

                if let show = currentShow {
                    CurrentShowContentView(show: show, formatter: formatter)
                } else {
                    CurrentShowEmptyStateView(onAddShow: {
                        isShowingAddShowCoordinator = true
                    })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet()
            }
        }
    }
}

// MARK: - Current Show Content

/// 首页 V3（2026-07 功能卡设计稿）：
/// 全幅 3:4 海报 + 三态秒级倒计时卡 + 阶段推荐 chips + 四张功能卡（内嵌真实预览）。
/// 布局与色板令牌见 HomeCountdownCard / HomeFeatureCards / BSColor.Home。
private struct CurrentShowContentView: View {
    let show: Show
    let formatter: ShowDisplayFormatter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var roundTripPlans: [RoundTripPlan]
    @Query private var preparationPlans: [ShowPreparationPlan]

    private let session = CurrentShowSession()

    @State private var activeToolSheet: ToolSheet?

    /// 内容左右边距（设计稿 --space-5 = 20pt；海报全幅不受此约束）。
    private let homeInset: CGFloat = 20

    /// 状态栏 / 灵动岛高度；GeometryReader 在 ignoresSafeArea 后可能读到 0。
    private static var windowTopSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? 59
    }

    enum ToolSheet: Identifiable {
        case candidateSongs, roundTrip, preparation, fragments
        var id: Self { self }
    }

    private var snapshot: CurrentShowSnapshot {
        session.snapshot(
            for: show,
            candidateGroups: candidateGroups,
            candidateSongs: candidateSongs,
            roundTripPlans: roundTripPlans,
            preparationPlans: preparationPlans
        )
    }

    private var summary: ShowToolSummary { snapshot.summary }

    private var roundTripPlan: RoundTripPlan? {
        roundTripPlans.first { $0.showID == show.id }
    }

    private var homeCandidateSongs: [CandidateSong] {
        let groupIDs = Set(candidateGroups.filter { $0.showID == show.id }.map(\.id))
        return candidateSongs
            .filter { groupIDs.contains($0.groupID) }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.everyMinute) { context in
                homeContent(geometry: geometry, now: context.date)
            }
        }
        // 让 GeometryReader 铺到状态栏下，才能读到真实 topInset，
        // 并把海报顶边 stretch 垫进状态栏。
        .ignoresSafeArea(edges: .top)
        .sheet(item: $activeToolSheet) { tool in
            NavigationStack {
                Group {
                    switch tool {
                    case .candidateSongs: CandidateSongsView(show: show)
                    case .roundTrip: RoundTripPlanView(show: show)
                    case .preparation: ShowPreparationView(show: show)
                    case .fragments: ShowFragmentListView(show: show)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func toolSheet(for kind: HomeFeatureKind) -> ToolSheet {
        switch kind {
        case .setlist: return .candidateSongs
        case .route: return .roundTrip
        case .prepare: return .preparation
        case .fragment: return .fragments
        }
    }

    @ViewBuilder
    private func homeContent(geometry: GeometryProxy, now: Date) -> some View {
        let timeState = CurrentShowTimeState(show: show, now: now)
        let phase = HomeShowPhase(timeState: timeState, now: now)
        // GeometryReader 受同层 AmbientBackground 影响可能宽于屏幕，
        // 与旧版 HomeLayoutMetrics 一样用 UIScreen 宽度封顶（内容列居中回落到真实视口）。
        let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
        // GeometryReader 在 ignoresSafeArea 后 safeAreaInsets 可能为 0，
        // 改用窗口安全区，保证状态栏垫条高度正确。
        let topInset = max(geometry.safeAreaInsets.top, Self.windowTopSafeAreaInset)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroStage(
                    phase: phase,
                    timeState: timeState,
                    width: viewportWidth,
                    topInset: topInset
                )

                HomeCountdownCard(show: show)
                    .padding(.horizontal, homeInset)
                    .padding(.top, -22)

                HomeFeatureCardsSection(
                    show: show,
                    phase: phase,
                    summary: summary,
                    candidateSongs: homeCandidateSongs,
                    roundTripPlan: roundTripPlan,
                    preparationPlan: preparationPlans.first { $0.showID == show.id },
                    onOpen: { kind in activeToolSheet = toolSheet(for: kind) },
                    onOpenMap: openDepartureMapForCurrentPlan
                )
                .padding(.horizontal, homeInset)
                .padding(.top, 18)
            }
            .padding(.bottom, BSLayout.tabBarContentInset + 28)
            .frame(width: viewportWidth)
            .frame(width: geometry.size.width, alignment: .center)
            .frame(minHeight: geometry.size.height, alignment: .top)
        }
    }

    // MARK: Hero（全幅 3:4 海报 + 顶边 stretch 进状态栏 + kicker + scrim 元信息）

    private func heroStage(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        width: CGFloat,
        topInset: CGFloat
    ) -> some View {
        NavigationLink {
            ShowDetailView(show: show)
        } label: {
            heroVisual(phase: phase, timeState: timeState, width: width, topInset: topInset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("现场封面，\(show.name)，点按进入详情")
        .accessibilityAddTraits(.isButton)
    }

    private func heroVisual(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        width: CGFloat,
        topInset: CGFloat
    ) -> some View {
        let height = width * 4.0 / 3.0
        // 顶边条带略伸进海报，被清晰层盖住，避免 blur 在接缝处发糊边。
        let bleedOverlap: CGFloat = 18
        let bleedHeight = max(0, topInset) + bleedOverlap

        return ZStack(alignment: .top) {
            if bleedHeight > 0 {
                heroTopBleed(
                    phase: phase,
                    width: width,
                    posterHeight: height,
                    bleedHeight: bleedHeight
                )
            }

            posterArtwork(phase: phase, width: width, height: height)
                .overlay { heroScrim }
                .overlay { heroGlow(phase: phase, width: width, height: height) }
                .overlay(alignment: .bottomLeading) {
                    heroMeta(phase: phase, timeState: timeState)
                        .padding(.horizontal, homeInset)
                        .padding(.bottom, 30)
                }
                .overlay(alignment: .bottom) { heroEdgeLine }
                .offset(y: max(0, topInset))
        }
        .frame(width: width, height: height + max(0, topInset), alignment: .top)
        .clipped()
    }

    /// 封面顶边向上渗出的光晕：重模糊 + 低不透明度 + 向上很快消散。
    /// 不是垫满状态栏的色段，更像封面边缘漫出来的一圈气。
    private func heroTopBleed(
        phase: HomeShowPhase,
        width: CGFloat,
        posterHeight: CGFloat,
        bleedHeight: CGFloat
    ) -> some View {
        // 取稍宽顶边 → 大幅模糊后只剩色温；竖直略拉高，像光从封面缝里溢出来。
        let sourceStrip = min(max(bleedHeight * 0.7, 36), 56)
        let stretch = (bleedHeight + 36) / sourceStrip

        return Color.clear
            .frame(width: width, height: bleedHeight)
            .background(alignment: .bottom) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    alignment: .center,
                    enforcesAspectRatio: false,
                    cornerRadius: 0
                )
                .frame(width: width, height: posterHeight)
                .frame(width: width, height: sourceStrip, alignment: .top)
                .scaleEffect(x: 1.12, y: stretch, anchor: .bottom)
                .saturation(phase == .ended ? 0.5 : 0.9)
                .brightness(phase == .ended ? -0.02 : 0.04)
                .blur(radius: 36)
                .opacity(phase == .ended ? 0.28 : 0.4)
            }
            .mask(
                // 只在贴海报的下半段有存在感，上半（状态栏顶）几乎透明，不「塞满」。
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white.opacity(0.12), location: 0.35),
                        .init(color: .white.opacity(0.45), location: 0.62),
                        .init(color: .white.opacity(0.85), location: 0.88),
                        .init(color: .white, location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipped()
            .allowsHitTesting(false)
    }

    private func posterArtwork(phase: HomeShowPhase, width: CGFloat, height: CGFloat) -> some View {
        ShowCoverImageView(
            urlString: show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            alignment: .center,
            enforcesAspectRatio: false,
            cornerRadius: 0
        )
        .frame(width: width, height: height)
        .saturation(phase == .ended ? 0.72 : 1.0)
        .brightness(phase == .ended ? -0.05 : 0)
        .clipped()
    }

    /// 设计稿 hero-scrim：顶部更轻，与状态栏 stretch 条带衔接；底部 98% 收进内容区。
    private var heroScrim: some View {
        LinearGradient(
            stops: [
                .init(color: BSColor.Home.background.opacity(0.14), location: 0.00),
                .init(color: BSColor.Home.background.opacity(0.10), location: 0.22),
                .init(color: BSColor.Home.background.opacity(0.22), location: 0.48),
                .init(color: BSColor.Home.background.opacity(0.86), location: 0.74),
                .init(color: BSColor.Home.background.opacity(0.98), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 设计稿 hero-glow：金 / 蓝 / 紫三束舞台光，screen 混合；live 全开，ended 收半。
    private func heroGlow(phase: HomeShowPhase, width: CGFloat, height: CGFloat) -> some View {
        let opacity: Double = phase == .ended ? 0.45 : (phase == .live ? 1.0 : 0.92)
        return ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Home.accent.opacity(0.36), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.39
                ))
                .frame(width: width * 0.78, height: height * 0.36)
                .position(x: width * 0.50, y: height * 0.16)

            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Home.route.opacity(0.30), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.26
                ))
                .frame(width: width * 0.52, height: height * 0.34)
                .position(x: width * 0.16, y: height * 0.70)

            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Home.prepare.opacity(0.28), .clear],
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

    /// 海报下缘一线暖金（设计稿 hero-stage::after）。
    private var heroEdgeLine: some View {
        LinearGradient(
            colors: [.clear, BSColor.Home.accent.opacity(0.28), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }

    private func heroMeta(phase: HomeShowPhase, timeState: CurrentShowTimeState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kickerPill(phase: phase, timeState: timeState)
                .padding(.bottom, 10)

            Text(dateLine(timeState: timeState))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BSColor.Home.foreground.opacity(0.78))
                .padding(.bottom, 8)

            Text(show.name)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundColor(BSColor.Home.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)

            if !locationText.isEmpty {
                Text(locationText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(BSColor.Home.foreground.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private func kickerPill(phase: HomeShowPhase, timeState: CurrentShowTimeState) -> some View {
        let text = phase == .inactive ? timeState.title : phase.kickerText(city: show.city)
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
        case .pre: return BSColor.Home.accent
        case .live: return BSColor.Home.live
        case .ended, .inactive: return BSColor.Home.dim
        }
    }

    private func kickerTextColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Home.accent
        case .live: return BSColor.Home.liveTitle
        case .ended, .inactive: return BSColor.Home.foreground.opacity(0.72)
        }
    }

    private func kickerTint(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Home.background.opacity(0.38)
        case .live: return Color(red: 0.31, green: 0.09, blue: 0.13).opacity(0.42)
        case .ended, .inactive: return BSColor.Home.background.opacity(0.45)
        }
    }

    private func kickerBorderColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Home.accent.opacity(0.28)
        case .live: return BSColor.Home.live.opacity(0.42)
        case .ended, .inactive: return Color.white.opacity(0.14)
        }
    }

    /// 设计稿 event-date 行：日期时间 · 约 X 分钟 / 小时（音乐节跨天已有「每日 HH:mm」，不追加时长）。
    private func dateLine(timeState: CurrentShowTimeState) -> String {
        let base = formatter.dateText(for: show)
        guard show.type != .musicFestival, let start = timeState.effectiveStartTime else {
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
        return "\(base) · 约 \(CurrentShowTimeState.defaultDurationHours(for: show.type)) 小时"
    }

    @MainActor
    private func openDepartureMapForCurrentPlan() {
        guard let plan = roundTripPlan else { return }
        if let url = plan.savedDepartureNavigationURL {
            UIApplication.shared.open(url)
            return
        }
        if let url = DeparturePlanSession.appleMapsDirectionsURL(origin: plan.departureOrigin, destination: plan.departureDestination) {
            UIApplication.shared.open(url)
        }
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
}

// MARK: - Empty State

private struct CurrentShowEmptyStateView: View {
    let onAddShow: () -> Void

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
    }
}

// MARK: - Countdown View

private extension CurrentShowTimeState {
    @MainActor
    @ViewBuilder
    func countdownView() -> some View {
        switch kind {
        case .today:
            Text("就是今天")
                .font(.system(size: 40, weight: .light))
                .tracking(1)
                .bsGradientText()
        case .ended:
            Text("已结束")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .canceled:
            Text("已取消")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .postponed:
            Text("待定")
                .font(.system(size: 44, weight: .light))
                .bsGradientText()
        default:
            HStack(alignment: .lastTextBaseline, spacing: BSSpacing.sm) {
                Text(countdownNumber)
                    .font(BSFont.display)
                    .bsGradientText()
                    .minimumScaleFactor(0.6)

                Text(countdownUnit)
                    .font(BSFont.title)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
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
                type: .concert,
                source: .link
            ),
            ShowDraft(
                name: "绿洲音乐节2.0·湖州吴兴站",
                date: date(2026, 6, 27),
                city: "湖州",
                venueName: "吴乐湾音乐广场",
                artist: "刘雨昕, 姚琛, 二手玫瑰, DOUDOU, 椿乐队, 裁缝铺, 麻园诗人, 梅卡德尔, 石岩, 声音碎片, 声音玩具",
                type: .musicFestival,
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
