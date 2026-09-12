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
    @Environment(CompanionSharingCoordinator.self) private var companionCoordinator
    @Query private var rootShows: [Show]
    @AppStorage(OnboardingCompletionStore.appStorageKey) private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var hasResolvedOnboardingRoute = false
    @State private var isShowingOnboarding = false
    @State private var selectedTab: BeforeShowTab = .current
    @State private var ceremonyPendingDetail: FootprintDetailDestination?
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    /// Root owns only cross-feature tab dispatch. The Current Show feature root owns
    /// the concrete notification destination and never mutates CurrentShowSelection.
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    private var companionResultMessage: String? {
        if let accepted = companionCoordinator.pendingAcceptMessage {
            return accepted
        }
        if companionCoordinator.lastErrorKind == .statusSyncPending {
            return companionCoordinator.lastErrorMessage
        }
        return nil
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
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
        .sheet(isPresented: $proOfferRouter.shouldPresentProSheet) {
            ProPaywallSheetView(initiallyShowsWinback: proOfferRouter.shouldShowWinbackOffer)
        }
        .alert(
            BSLocalization.text("同行"),
            isPresented: Binding(
                get: {
                    hasFinishedSplash
                        && hasResolvedOnboardingRoute
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
        .task {
            // A CloudKit share can cold-launch the app before AppDelegate dependencies are
            // wired. Only a real pending acceptance should block onboarding resolution;
            // ordinary launches must not wait for a CloudKit discovery round-trip.
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
            if ProcessInfo.processInfo.arguments.contains("--open-listening") || ProcessInfo.processInfo.arguments.contains("--listen-fixture") { selectedTab = .listen }
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

    private func dismissCompanionResultMessage() {
        _ = companionCoordinator.consumePendingAcceptMessage()
        if companionCoordinator.lastErrorKind == .statusSyncPending {
            _ = companionCoordinator.consumeLastErrorMessage()
        }
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
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            CurrentShowFeatureRootView(
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

            ListeningFeatureRootView(isActive: selectedTab == .listen)
                .tabItem { Label(BeforeShowTab.listen.localizedTitle, systemImage: BeforeShowTab.listen.iconName) }
                .tag(BeforeShowTab.listen)

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
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: ceremonyPendingDetail) { _, newValue in
            if newValue != nil, selectedTab != .footprints {
                selectedTab = .footprints
            }
        }
    }
}
