import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var rootShows: [Show]
    @AppStorage(OnboardingCompletionStore.appStorageKey) private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var hasResolvedOnboardingRoute = false
    @State private var isShowingOnboarding = false
    @State private var selectedTab: BeforeShowTab = .current
    /// 仪式结束后,RootView 写入这个目标 → 切到 .footprints → FootprintsView
    /// 在 onChange 触发自己的 push。详见 `presentCeremonyMemoryNavigation`。
    @State private var ceremonyPendingDetail: FootprintDetailDestination?
    /// 长按图标「Pro 限时优惠」Quick Action 的 deep link 路由。
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    /// 点击本地通知的 deep link 路由。RootView 只负责切到「当前」tab，
    /// 具体目标（首页 / 记忆碎片）由 CurrentShowHomeView 消费。
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    /// 语言变化要刷新所有 BSLocalization 文案，但不能换掉 RootView 的身份：
    /// 用 .id(language) 会重建整棵树，把 tab / Settings / 仪式等状态一起丢掉。
    /// 这里只订阅变化触发 body 重算，导航与呈现状态原样保留。
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasFinishedSplash, hasResolvedOnboardingRoute {
                if isShowingOnboarding {
                    OnboardingFlowView(onCompleted: completeOnboarding)
                        .transition(.opacity)
                } else {
                    mainTabView
                        .transition(.opacity)
                }
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
        .sheet(isPresented: $proOfferRouter.shouldPresentProSheet) {
            ProPaywallSheetView(initiallyShowsWinback: proOfferRouter.shouldShowWinbackOffer)
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, deepLink in
            // 通知落地的前提是先站在「当前」tab；目标的消费在首页。
            guard deepLink != nil else { return }
            selectedTab = .current
        }
        .task {
            resolveOnboardingRouteIfNeeded()
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
            FootprintDebugSeeder.seedIfRequested(in: modelContext)
            if ProcessInfo.processInfo.arguments.contains("--open-footprints") {
                selectedTab = .footprints
            }
            if ProcessInfo.processInfo.arguments.contains("--open-pro-paywall") {
                ProOfferDeepLinkRouter.shared.routeToPro()
            }
            if ProcessInfo.processInfo.arguments.contains("--open-pro-winback") {
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
        }
        #endif
    }

    private func resolveOnboardingRouteIfNeeded() {
        guard !hasResolvedOnboardingRoute else { return }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--open-onboarding") {
            isShowingOnboarding = true
            hasResolvedOnboardingRoute = true
            return
        }
        if arguments.contains(where: { argument in
            argument.hasPrefix("--seed-")
                || argument == "--open-footprints"
                || argument == "--open-pro-paywall"
                || argument == "--open-pro-winback"
        }) {
            isShowingOnboarding = false
            hasResolvedOnboardingRoute = true
            return
        }
        #endif

        let hasShows = !rootShows.isEmpty
        if OnboardingRoutingPolicy.shouldMigrateExistingUser(
            hasCompleted: hasCompletedOnboarding,
            hasShows: hasShows
        ) {
            hasCompletedOnboarding = true
        }
        isShowingOnboarding = OnboardingRoutingPolicy.shouldPresent(
            hasCompleted: hasCompletedOnboarding,
            hasShows: hasShows
        )
        hasResolvedOnboardingRoute = true
    }

    private func completeOnboarding(showID _: UUID) {
        hasCompletedOnboarding = true
        if reduceMotion {
            isShowingOnboarding = false
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingOnboarding = false
            }
        }
    }

    /// System TabView so iOS 26+ applies Liquid Glass to the tab bar.
    /// Both tabs stay mounted and keep the system tab bar visible across in-tab navigation.
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            CurrentShowHomeView(
                isPlaybackActive: selectedTab == .current,
                ceremonyPendingDetail: $ceremonyPendingDetail
            )
            .tabItem {
                Label(
                    BeforeShowTab.current.localizedTitle,
                    systemImage: BeforeShowTab.current.iconName
                )
            }
            .tag(BeforeShowTab.current)

            FootprintsView(
                pendingDetailTarget: ceremonyPendingDetail
            )
            .tabItem {
                Label(
                    BeforeShowTab.footprints.localizedTitle,
                    systemImage: BeforeShowTab.footprints.iconName
                )
            }
            .tag(BeforeShowTab.footprints)
        }
        // 系统 TabView(Liquid Glass)自带交叉淡入,自定义 transition 会和它打架;
        // 这里只补一个轻触觉,让切 tab 有确认感。
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: ceremonyPendingDetail) { _, newValue in
            // 仪式 sheet 关闭并要求跳到足迹时,切到 footprints tab。
            // FootprintsView 自己的 onChange 监听同一值并触发 push。
            if newValue != nil, selectedTab != .footprints {
                selectedTab = .footprints
            }
        }
    }
}
