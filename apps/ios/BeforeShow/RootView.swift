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
            CurrentShowHomeView(onOpenMyShows: { selectedTab = .myShows })
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
    var onOpenMyShows: () -> Void = {}

    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var isShowingAddShowCoordinator = false
    @State private var toast: BSToastPayload?
    #if DEBUG
    @State private var isShowingSettings = false
    #endif

    private let session = CurrentShowSession()
    private let formatter = ShowDisplayFormatter()

    private var currentShow: Show? {
        session.selectCurrentShow(from: shows, manualSelection: selections.first)
    }

    var body: some View {
        NavigationStack {
            // AmbientBackground 的理想宽度可能超过屏幕（见 homeContent 的 UIScreen 封顶注释），
            // 这里一并封顶，避免内容被顶出屏幕。
            ZStack {
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)

                if let show = currentShow {
                    CurrentShowContentView(
                        show: show,
                        formatter: formatter,
                        onAddNextShow: { isShowingAddShowCoordinator = true },
                        onOpenMyShows: onOpenMyShows
                    )
                } else {
                    CurrentShowEmptyStateView(
                        onAddShow: { isShowingAddShowCoordinator = true },
                        onOpenMyShows: onOpenMyShows
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
            #if DEBUG
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
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
}

// MARK: - Home Overflow Menu

/// V4:封面右上角的安静溢出键(44pt),取代旧顶栏条带。设置与我的现场入口收在这里。
private struct HomeOverflowMenu: View {
    var onOpenMyShows: () -> Void

    var body: some View {
        Menu {
            NavigationLink {
                SettingsView()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Button(action: onOpenMyShows) {
                Label("我的现场", systemImage: "music.note.list")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground.opacity(0.85))
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("更多选项")
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

// MARK: - Current Show Content

/// 首页 V4(2026-07 全状态原型落地,design-exploration/home-v4-all-states.html):
/// 居中 3:4 封面 + 封面边缘漫光氛围;封面之后 20pt 停顿的扁倒计时 lockup;
/// 每个生命周期一张 Tip 卡;已结束 / 已取消给「添加下一场」动作区。
/// 倒计时与 Tip 组件见 HomeCountdownCard.swift(HomeCountdownLockup / HomeTipCard)。
private struct CurrentShowContentView: View {
    let show: Show
    let formatter: ShowDisplayFormatter
    var onAddNextShow: () -> Void
    var onOpenMyShows: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 内容左右边距(设计稿 --space-5 = 20pt;封面居中不受此约束)。
    private let contentInset: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.everyMinute) { context in
                homeContent(geometry: geometry, now: context.date)
            }
        }
    }

    @ViewBuilder
    private func homeContent(geometry: GeometryProxy, now: Date) -> some View {
        let timeState = CurrentShowTimeState(show: show, now: now)
        let phase = HomeShowPhase(timeState: timeState, now: now)
        // GeometryReader 受同层 AmbientBackground 影响可能宽于屏幕,
        // 与旧版 HomeLayoutMetrics 一样用 UIScreen 宽度封顶(内容列居中回落到真实视口)。
        let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
        // V4 封面为居中立起的 3:4 对象(原型 352pt 宽,窄机退回屏宽 - 40)。
        let coverWidth = min(352, viewportWidth - 40)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroStage(phase: phase, timeState: timeState, coverWidth: coverWidth)
                    .padding(.top, 8)

                HomeCountdownLockup(show: show)
                    .padding(.horizontal, 21)
                    .padding(.top, 20)

                HomeTipCard(
                    show: show,
                    phase: phase,
                    timeState: timeState,
                    onAddNextShow: onAddNextShow
                )
                .padding(.horizontal, contentInset)
                .padding(.top, 16)

                actionZone(timeState: timeState)
                    .padding(.horizontal, contentInset)
                    .padding(.top, 28)
            }
            .padding(.bottom, BSLayout.tabBarContentInset)
            .frame(width: viewportWidth)
            .frame(width: geometry.size.width, alignment: .center)
            .frame(minHeight: geometry.size.height, alignment: .top)
        }
    }

    // MARK: Hero(居中 3:4 封面 + scrim 元信息 + 右上角安静溢出键)

    private func heroStage(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        coverWidth: CGFloat
    ) -> some View {
        let coverHeight = coverWidth * 4.0 / 3.0
        return ZStack {
            NavigationLink {
                ShowDetailView(show: show)
            } label: {
                heroVisual(phase: phase, timeState: timeState, width: coverWidth, height: coverHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("现场封面,\(show.name),点按进入详情")
            .accessibilityAddTraits(.isButton)

            HomeOverflowMenu(onOpenMyShows: onOpenMyShows)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
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
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 15)
    }

    // MARK: 收束态动作区(已结束 / 已取消:一主一静)

    @ViewBuilder
    private func actionZone(timeState: CurrentShowTimeState) -> some View {
        if timeState.kind == .ended || timeState.kind == .canceled {
            VStack(spacing: 10) {
                Button(action: onAddNextShow) {
                    Text("添加下一场现场")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(Color(red: 0.039, green: 0.047, blue: 0.071))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(BSColor.Stage.foreground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button(action: onOpenMyShows) {
                    Text("看看我的现场")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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

    /// 设计稿 event-date 行:日期时间 · 约 X 分钟 / 小时(跨天「每日 HH:mm」已含区间,不追加时长)。
    private func dateLine(timeState: CurrentShowTimeState) -> String {
        let base = formatter.dateText(for: show)
        let isMultiDayWithoutEndClock: Bool = {
            guard let endDay = timeState.effectiveEndDate else { return false }
            let startDay = Calendar.current.startOfDay(for: timeState.effectiveDate)
            let endStart = Calendar.current.startOfDay(for: endDay)
            return endStart > startDay && timeState.effectiveEndTime == nil
        }()
        guard !isMultiDayWithoutEndClock, let start = timeState.effectiveStartTime else {
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
}

// MARK: - Empty State

private struct CurrentShowEmptyStateView: View {
    let onAddShow: () -> Void
    var onOpenMyShows: () -> Void = {}

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
        .overlay(alignment: .topTrailing) {
            HomeOverflowMenu(onOpenMyShows: onOpenMyShows)
                .padding(.trailing, 20)
                .padding(.top, 8)
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
