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
    @State private var companionDuplicateResolution: CompanionDuplicateResolution?
    @State private var companionDuplicateErrorMessage: String?
    @State private var companionAcceptanceMessage: String?
    @StateObject private var proOfferRouter = ProOfferDeepLinkRouter.shared
    /// Root owns only cross-feature tab dispatch. The Current Show feature root owns
    /// the concrete notification destination and never mutates CurrentShowSelection.
    @StateObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @ObservedObject private var languageController = AppLanguageController.shared

    private var companionResultMessage: String? {
        if let companionDuplicateErrorMessage {
            return companionDuplicateErrorMessage
        }
        if let companionAcceptanceMessage {
            return companionAcceptanceMessage
        }
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
            if companionDuplicateErrorMessage == nil,
               let result = companionCoordinator.pendingAcceptResult {
                Button(BSLocalization.text(
                    result.wasHistorical ? "查看足迹" : (result.becameCurrent ? "进入现场" : "查看这场现场")
                )) {
                    openAcceptedShow(result)
                }
            }
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
        .onChange(of: companionCoordinator.pendingAcceptMessage, initial: true) { _, message in
            if let message {
                companionAcceptanceMessage = message
            }
        }
        .onChange(of: rootShows.map(\.id)) { _, _ in
            refreshCompanionDuplicateResolution()
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
            refreshCompanionDuplicateResolution()
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

    private func openAcceptedShow(_ result: CompanionAcceptedImportResult) {
        if result.wasHistorical, let show = rootShows.first(where: { $0.id == result.showID }) {
            ceremonyPendingDetail = FootprintDetailDestination(show: show)
            selectedTab = .footprints
        } else if result.becameCurrent {
            selectedTab = .current
        } else {
            selectedTab = .current
            notificationRouter.route(to: NotificationDeepLink(showID: result.showID, destination: .home))
        }
        dismissCompanionResultMessage()
    }

    private func dismissCompanionResultMessage() {
        companionDuplicateErrorMessage = nil
        companionAcceptanceMessage = nil
        _ = companionCoordinator.consumePendingAcceptMessage()
        _ = companionCoordinator.consumePendingAcceptResult()
        if companionCoordinator.lastErrorKind == .statusSyncPending {
            _ = companionCoordinator.consumeLastErrorMessage()
        }
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
