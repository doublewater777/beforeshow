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
    @State private var companionDuplicateResolution: CompanionDuplicateResolution?
    @State private var companionDuplicateErrorMessage: String?
    @State private var companionToast: BSToastPayload?
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    init() {
        let isReturning = OnboardingCompletionStore.hasCompleted()
        _hasFinishedSplash = State(initialValue: isReturning)
        _hasResolvedOnboardingRoute = State(initialValue: isReturning)
    }

    private var companionResultMessage: String? {
        companionDuplicateErrorMessage
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

            CompanionPendingJoinHost(onJoinSuccess: presentCompanionToast)
        }
        .bsToastOverlay(companionToast)
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
        .sheet(isPresented: $proOfferRouter.shouldPresentProSheet) {
            ProPaywallSheetView(initiallyShowsWinback: proOfferRouter.shouldShowWinbackOffer)
        }
        .sheet(item: $companionDuplicateResolution) { resolution in
            CompanionDuplicateResolutionSheet(
                resolution: resolution,
                onMerge: { target in
                    resolveCompanionDuplicate(resolution, mergeInto: target)
                },
                onKeepSeparate: {
                    keepCompanionDuplicateSeparate(resolution)
                }
            )
        }
        .alert(
            BSLocalization.text("同行"),
            isPresented: Binding(
                get: {
                    hasFinishedSplash
                        && hasResolvedOnboardingRoute
                        && companionDuplicateResolution == nil
                        && companionResultMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        dismissCompanionResultMessage()
                    }
                }
            )
        ) {
            Button(BSLocalization.text("知道了"), role: .cancel) {
                dismissCompanionResultMessage()
            }
        } message: {
            Text(companionResultMessage ?? "")
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
            refreshCompanionDuplicateResolution()
        }
        .task {
            companionCoordinator.reloadPersistedAcceptedShares()
            if companionCoordinator.hasPendingAcceptedShares {
                await companionCoordinator.refreshAllLinkedShows(in: modelContext)
            }
            resolveOnboardingRouteIfNeeded(hasShowsOverride: persistedShowExists())
            refreshCompanionDuplicateResolution()
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
    private func presentCompanionToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        companionToast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if companionToast == payload { companionToast = nil }
        }
    }
    private func dismissCompanionResultMessage() {
        companionDuplicateErrorMessage = nil
        _ = companionCoordinator.consumePendingAcceptMessage()
        _ = companionCoordinator.consumePendingAcceptResult()
        if companionCoordinator.lastErrorKind == .statusSyncPending { _ = companionCoordinator.consumeLastErrorMessage() }
    }
    private func refreshCompanionDuplicateResolution() {
        guard companionDuplicateResolution == nil else { return }
        companionDuplicateResolution = CompanionDuplicateResolutionFinder.first(in: rootShows)
    }
    private func resolveCompanionDuplicate(
        _ resolution: CompanionDuplicateResolution,
        mergeInto target: Show
    ) {
        do {
            try CompanionDuplicateMerger.merge(
                imported: resolution.importedShow,
                into: target,
                in: modelContext
            )
            companionDuplicateResolution = nil
            dismissCompanionResultMessage()
            refreshCompanionDuplicateResolution()
        } catch {
            companionDuplicateErrorMessage = CompanionSharingCoordinator.userMessage(for: error)
            companionDuplicateResolution = nil
        }
    }
    private func keepCompanionDuplicateSeparate(_ resolution: CompanionDuplicateResolution) {
        if let sessionRecordName = resolution.importedShow.companionCloudRecordName {
            CompanionDuplicateResolutionStore.ignore(sessionRecordName: sessionRecordName)
        }
        companionDuplicateResolution = nil
        refreshCompanionDuplicateResolution()
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
