import SwiftData
import SwiftUI

enum OnboardingCompletionStore {
    static let appStorageKey = "has_completed_feature_onboarding_v1"

    static func hasCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: appStorageKey)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: appStorageKey)
    }
}

enum OnboardingRoutingPolicy {
    static func shouldPresent(hasCompleted: Bool, hasShows: Bool) -> Bool {
        !hasCompleted && !hasShows
    }

    static func shouldMigrateExistingUser(hasCompleted: Bool, hasShows: Bool) -> Bool {
        !hasCompleted && hasShows
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case beforeShow
    case showDay
    case afterShow
    case start

    var id: Int { rawValue }

    var analyticsValue: String {
        switch self {
        case .beforeShow: "before_show"
        case .showDay: "show_day"
        case .afterShow: "after_show"
        case .start: "start"
        }
    }

    var artworkName: String {
        switch self {
        case .beforeShow: "onboarding_before_show"
        case .showDay: "onboarding_show_day"
        case .afterShow: "onboarding_after_show"
        case .start: "onboarding_start"
        }
    }

    var phaseText: String {
        switch self {
        case .beforeShow: return BSLocalization.text("倒数")
        case .showDay: return BSLocalization.text("演出当天")
        case .afterShow: return BSLocalization.text("散场以后")
        case .start: return BSLocalization.text("现在开始")
        }
    }

    var title: String {
        switch self {
        case .beforeShow: return BSLocalization.text("不用打开，也在靠近")
        case .showDay: return BSLocalization.text("当天要看的，都在这一屏")
        case .afterShow: return BSLocalization.text("每一场，都收成一张唱片")
        case .start: return BSLocalization.text("下一场，从这里开始倒数")
        }
    }

    var bodyText: String {
        switch self {
        case .beforeShow:
            return BSLocalization.text("主屏幕和锁屏替你数着那一天，\n演出的歌也能提前听熟。")
        case .showDay:
            return BSLocalization.text("路线、天气、开场时间一眼就有；\n音乐节按舞台看下一位。")
        case .afterShow:
            return BSLocalization.text("给这一晚打个分，\n照片和小记一起收进足迹。")
        case .start:
            return BSLocalization.text("粘贴购票平台的链接，\n名称、时间和地点会自动填好。")
        }
    }
}

struct OnboardingFlowView: View {
    let onCompleted: () -> Void

    init(
        initialPage: OnboardingPage = .beforeShow,
        onCompleted: @escaping () -> Void
    ) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--onboarding-page-start") {
            _page = State(initialValue: .start)
        } else {
            _page = State(initialValue: initialPage)
        }
        #else
        _page = State(initialValue: initialPage)
        #endif
        self.onCompleted = onCompleted
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: OnboardingPage = .beforeShow
    @State private var isShowingAddShow = false
    @State private var hasCapturedStart = false

    var body: some View {
        ZStack {
            onboardingBackground

            artwork
                .id(page)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: BSMotion.emphasis), value: page)

            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { item in
                    OnboardingPageView(
                        page: item,
                        isActive: item == page,
                        onAddShow: {
                            isShowingAddShow = true
                            ProductAnalytics.capture(.onboardingAddShowTapped)
                        }
                    )
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            chrome
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddShow) {
            AddShowCoordinatorSheet { _ in
                completeOnboarding(method: "add_show")
            }
        }
        .onAppear {
            guard !hasCapturedStart else { return }
            hasCapturedStart = true
            ProductAnalytics.capture(.onboardingStarted)
        }
        .onChange(of: page) { _, newPage in
            ProductAnalytics.capture(.onboardingPageViewed(page: newPage.analyticsValue))
            ProductAnalytics.screen("onboarding_\(newPage.analyticsValue)")
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            BSColor.Stage.background
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.30), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.16), .clear],
                center: UnitPoint(x: 1, y: 0.06),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 600)
                .overlay {
                    Image(page.artworkName)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    // 顶部压暗，保证「开场前」与「跳过」可读。
                    LinearGradient(
                        colors: [BSColor.Stage.background.opacity(0.75), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                }
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text("开场前")
                    .font(BSFont.V3.small.weight(.semibold))
                    .tracking(2.6)
                    .foregroundStyle(BSColor.Stage.foreground)

                Spacer()

                Button(action: skipOnboarding) {
                    Text(BSLocalization.text("跳过"))
                        .font(BSFont.V3.small.weight(.medium))
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BSSpacing.roomy)

            Spacer()

            if page != .start {
                HStack(spacing: BSSpacing.md) {
                    pageIndicator
                    Spacer()
                    Button(BSLocalization.text("继续"), action: advance)
                        .buttonStyle(OnboardingContinueButtonStyle())
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.bottom, BSSpacing.sm)
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.allCases) { item in
                Capsule()
                    .fill(item == page ? BSColor.Stage.foreground : BSColor.Stage.dim)
                    .frame(width: item == page ? 22 : 6, height: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: BSMotion.interface), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            BSLocalization.format(
                "第 %lld 页，共 %lld 页",
                Int64(page.rawValue + 1),
                Int64(OnboardingPage.allCases.count)
            )
        )
    }

    private func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        move(to: next)
    }

    private func move(to destination: OnboardingPage) {
        if reduceMotion {
            page = destination
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                page = destination
            }
        }
    }

    private func skipOnboarding() {
        ProductAnalytics.capture(.onboardingSkipped(fromPage: page.analyticsValue))
        completeOnboarding(method: "skip")
    }

    private func completeOnboarding(method: String) {
        OnboardingCompletionStore.markCompleted()
        ProductAnalytics.capture(.onboardingCompleted(method: method))
        onCompleted()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    let onAddShow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(page.phaseText)
                    .font(BSFont.V3.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(BSColor.Stage.accent)

                Text(page.title)
                    .font(BSFont.Editorial.song(size: 30))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, BSSpacing.sm)

                Text(page.bodyText)
                    .font(BSFont.V3.body)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, BSSpacing.compact)
            }
            .padding(.horizontal, BSSpacing.lg)
            .opacity(textAppeared ? 1 : 0)
            .offset(y: textAppeared ? 0 : 10)

            if page == .start {
                Button(BSLocalization.text("添加我的第一个现场"), action: onAddShow)
                    .buttonStyle(BSPrimaryButtonStyle())
                    .padding(.horizontal, BSSpacing.lg)
                    .padding(.top, BSSpacing.xl + BSSpacing.lg)
                    .padding(.bottom, BSSpacing.sm)
                    .opacity(textAppeared ? 1 : 0)
            } else {
                // 与第 4 页主按钮占位对齐，底部 chrome（页码 + 继续）浮在这里。
                Color.clear.frame(height: BSLayout.minTouchTarget + BSSpacing.xl + BSSpacing.lg + BSSpacing.sm)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { runEntrance() }
        .onChange(of: isActive) { _, active in
            if active { runEntrance() }
        }
    }

    private func runEntrance() {
        guard !reduceMotion else {
            textAppeared = true
            return
        }
        textAppeared = false
        withAnimation(.easeOut(duration: BSMotion.interface).delay(0.06)) {
            textAppeared = true
        }
    }
}

private struct OnboardingContinueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BSFont.V3.body.weight(.semibold))
            .foregroundStyle(BSColor.Stage.background)
            .padding(.horizontal, 22)
            .frame(minWidth: 92, minHeight: BSLayout.minTouchTarget)
            .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
