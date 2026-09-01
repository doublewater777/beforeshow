import PostHog
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

    var phaseText: String {
        switch self {
        case .beforeShow: BSLocalization.text("开场前")
        case .showDay: BSLocalization.text("现场当天")
        case .afterShow: BSLocalization.text("散场以后")
        case .start: BSLocalization.text("现在开始")
        }
    }

    var title: String {
        switch self {
        case .beforeShow: BSLocalization.text("不用打开，也在靠近")
        case .showDay: BSLocalization.text("重要的内容，抬手就能找到")
        case .afterShow: BSLocalization.text("把这一晚，轻轻留住")
        case .start: BSLocalization.text("从下一场开始，慢慢靠近")
        }
    }

    var bodyText: String {
        switch self {
        case .beforeShow:
            BSLocalization.text("主屏幕和锁屏都替你数着那一天，再在几个值得记一下的节点轻轻提醒。")
        case .showDay:
            BSLocalization.text("选择一张演出流程、阵容安排或时间图片，保存到这场现场，需要时快速打开。")
        case .afterShow:
            BSLocalization.text("照片、视频和小记按现场阶段收在一起，散场时再用五档情绪评价，为这一晚收尾。")
        case .start:
            BSLocalization.text("开场前的期待、现场当天的重要内容和散场后的记忆，都收在同一场现场里。")
        }
    }
}

struct OnboardingFlowView: View {
    let onCompleted: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: OnboardingPage = .beforeShow
    @State private var isShowingAddShow = false
    @State private var pendingAddedShowID: UUID?
    @State private var hasCapturedStart = false

    var body: some View {
        ZStack {
            onboardingBackground

            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { item in
                    OnboardingPageView(page: item) {
                        isShowingAddShow = true
                        PostHogSDK.shared.capture("onboarding_add_show_tapped")
                    }
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            chrome
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddShow, onDismiss: completeAfterAddIfNeeded) {
            AddShowCoordinatorSheet { showID in
                pendingAddedShowID = showID
            }
        }
        .onAppear {
            guard !hasCapturedStart else { return }
            hasCapturedStart = true
            PostHogSDK.shared.capture("onboarding_started")
        }
        .onChange(of: page) { _, newPage in
            PostHogSDK.shared.capture(
                "onboarding_page_viewed",
                properties: ["page": newPage.analyticsValue]
            )
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            BSColor.Stage.background
            Image("splash_bg")
                .resizable()
                .scaledToFill()
                .saturation(0.72)
                .brightness(-0.28)
                .opacity(0.50)
                .accessibilityHidden(true)
            LinearGradient(
                colors: [
                    BSColor.Stage.background.opacity(0.18),
                    BSColor.Stage.background.opacity(0.64),
                    BSColor.Stage.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text("开场前")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.6)
                    .foregroundColor(BSColor.Stage.foreground)

                Spacer()

                if page != .start {
                    Button {
                        PostHogSDK.shared.capture(
                            "onboarding_skipped",
                            properties: ["from_page": page.analyticsValue]
                        )
                        move(to: .start)
                    } label: {
                        Text(BSLocalization.text("跳过"))
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.muted)
                            .frame(minWidth: 64, minHeight: BSLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(BSLocalization.text("直接前往添加第一个现场"))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, BSSpacing.xl + BSSpacing.md)

            Spacer()

            HStack(spacing: BSSpacing.md) {
                pageIndicator
                Spacer()
                if page != .start {
                    Button(BSLocalization.text("继续"), action: advance)
                        .buttonStyle(OnboardingContinueButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, BSSpacing.xl + BSSpacing.lg)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.allCases) { item in
                Capsule()
                    .fill(item == page ? BSColor.Stage.foreground : Color.white.opacity(0.20))
                    .frame(width: item == page ? 22 : 6, height: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: page)
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

    private func completeAfterAddIfNeeded() {
        guard let showID = pendingAddedShowID else { return }
        pendingAddedShowID = nil
        OnboardingCompletionStore.markCompleted()
        PostHogSDK.shared.capture("onboarding_completed")
        onCompleted(showID)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let onAddShow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visualAppeared = false
    @State private var textAppeared = false
    @State private var bodyAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case .beforeShow:
                    OnboardingWidgetFeatureVisual()
                case .showDay:
                    OnboardingTimetableFeatureVisual()
                case .afterShow:
                    OnboardingMemoryFeatureVisual()
                case .start:
                    OnboardingStartFeatureVisual()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: page == .start ? 405 : 430)
            .scaleEffect(visualAppeared ? 1 : 0.92)
            .opacity(visualAppeared ? 1 : 0)

            Spacer(minLength: 0)

            Text(page.phaseText)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.3)
                .foregroundColor(BSColor.Stage.accent)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)

            Text(page.title)
                .font(.custom("Songti SC", size: page == .start ? 36 : 32, relativeTo: .largeTitle))
                .foregroundColor(BSColor.Stage.foreground)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)

            Text(page.bodyText)
                .font(.system(size: 13))
                .foregroundColor(BSColor.Stage.muted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .opacity(bodyAppeared ? 1 : 0)
                .offset(y: bodyAppeared ? 0 : 10)

            if page == .start {
                Button(BSLocalization.text("添加我的第一个现场"), action: onAddShow)
                    .buttonStyle(BSPrimaryButtonStyle())
                    .padding(.top, 26)
                    .opacity(bodyAppeared ? 1 : 0)
                    .offset(y: bodyAppeared ? 0 : 10)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 58)
        .padding(.bottom, BSSpacing.xl * 3 + BSSpacing.sm)
        .accessibilityElement(children: .contain)
        .onAppear { runEntrance() }
        .onChange(of: page) { _, _ in runEntrance() }
    }

    private func runEntrance() {
        guard !reduceMotion else {
            visualAppeared = true
            textAppeared = true
            bodyAppeared = true
            return
        }
        visualAppeared = false
        textAppeared = false
        bodyAppeared = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            visualAppeared = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.35)) {
                textAppeared = true
            }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.3)) {
                bodyAppeared = true
            }
        }
    }
}

private struct OnboardingContinueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 22)
            .frame(minWidth: 92, minHeight: BSLayout.minTouchTarget)
            .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 15))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
