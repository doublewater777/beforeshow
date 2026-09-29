import SwiftData
import SwiftUI
extension UUID: @retroactive Identifiable { public var id: UUID { self } }
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
    @Query private var rootShows: [Show]
    @AppStorage(OnboardingCompletionStore.appStorageKey) private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var hasResolvedOnboardingRoute = false
    @State private var isShowingOnboarding = false
    @State private var selectedTab: BeforeShowTab = .current
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    init() {
        let isReturning = OnboardingCompletionStore.hasCompleted()
        _hasFinishedSplash = State(initialValue: isReturning)
        _hasResolvedOnboardingRoute = State(initialValue: isReturning)
    }

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

            CompanionPendingJoinHost()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
        .sheet(isPresented: $proOfferRouter.shouldPresentProSheet) {
            ProPaywallSheetView(initiallyShowsWinback: proOfferRouter.shouldShowWinbackOffer)
        }
        .onChange(of: notificationRouter.featureRootDeepLink) { _, deepLink in
            guard deepLink != nil else { return }
            selectedTab = .current
        }
        .onChange(of: rootShows.map(\.id)) { _, _ in
            if isShowingOnboarding, !rootShows.isEmpty {
                hasCompletedOnboarding = true
                isShowingOnboarding = false
            }
        }
        .task {
            companionCoordinator.reloadPersistedAcceptedShares()
            if companionCoordinator.hasPendingAcceptedShares {
                await companionCoordinator.refreshAllLinkedShows(in: modelContext)
            }
            resolveOnboardingRouteIfNeeded(hasShowsOverride: persistedShowExists())
            if notificationRouter.featureRootDeepLink != nil {
                selectedTab = .current
            }
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
            FootprintDebugSeeder.seedIfRequested(in: modelContext)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--open-listening") || args.contains("--listen-fixture") { selectedTab = .listen }
            if args.contains("--open-footprints") { selectedTab = .footprints }
            if args.contains("--open-pro-paywall") { ProOfferDeepLinkRouter.shared.routeToPro() }
            if args.contains("--open-pro-winback") { ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true) }
        }
        #endif
    }
    private func persistedShowExists() -> Bool {
        var descriptor = FetchDescriptor<Show>()
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }
    private func resolveOnboardingRouteIfNeeded(hasShowsOverride: Bool? = nil) {
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
                || argument == "--open-listening"
                || argument == "--listen-fixture"
                || argument == "--open-pro-paywall"
                || argument == "--open-pro-winback"
        }) {
            isShowingOnboarding = false
            hasResolvedOnboardingRoute = true
            return
        }
        #endif

        let hasShows = hasShowsOverride ?? !rootShows.isEmpty
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
    private func completeOnboarding() {
        hasCompletedOnboarding = true
        if reduceMotion {
            isShowingOnboarding = false
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingOnboarding = false
            }
        }
    }
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(BeforeShowTab.current.localizedTitle, systemImage: BeforeShowTab.current.iconName, value: .current) {
                CurrentShowFeatureRootView(
                    isPlaybackActive: selectedTab == .current
                )
            }
            .accessibilityIdentifier("root.tab.current")

            Tab(BeforeShowTab.listen.localizedTitle, systemImage: BeforeShowTab.listen.iconName, value: .listen) {
                ListeningFeatureRootView(isActive: selectedTab == .listen)
            }
            .accessibilityIdentifier("root.tab.listen")

            Tab(BeforeShowTab.footprints.localizedTitle, systemImage: BeforeShowTab.footprints.iconName, value: .footprints) {
                FootprintsView()
            }
            .accessibilityIdentifier("root.tab.footprints")
        }
        .modifier(ListeningRootChromeModifier(selectedTab: $selectedTab))
        .modifier(FeedbackShakeShortcutModifier())
        // Keep system nav chrome neutral so tint does not leak into child controls.
        .tint(BSColor.Stage.foreground)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}
