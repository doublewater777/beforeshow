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
    @State private var ceremonyPendingDetail: FootprintDetailDestination?
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    /// Root owns only cross-feature tab dispatch. The Current Show feature root owns
    /// the concrete notification destination and never mutates CurrentShowSelection.
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
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
        .onChange(of: notificationRouter.featureRootDeepLink) { _, deepLink in
            guard deepLink != nil else { return }
            selectedTab = .current
        }
        .task {
            resolveOnboardingRouteIfNeeded()
            if notificationRouter.featureRootDeepLink != nil {
                selectedTab = .current
            }
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
