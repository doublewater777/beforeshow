import Foundation
import PostHog
import RevenueCat
import SwiftData
import SwiftUI
import UserNotifications

@main
struct BeforeShowApp: App {
    @UIApplicationDelegateAdaptor(BeforeShowAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var languageController = AppLanguageController.shared
    @State private var companionCoordinator = CompanionSharingCoordinator()
    @State private var lastLocalMediaMaintenanceAt: Date?
    @State private var isLocalMediaMaintenanceRunning = false

    private let modelContainer: ModelContainer

    private static var isRunningHostedUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCInjectBundleInto"] != nil
    }

    init() {
        let isRunningHostedUnitTests = Self.isRunningHostedUnitTests

        do {
            modelContainer = try ModelContainerFactory.make(
                isStoredInMemoryOnly: isRunningHostedUnitTests
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        if !isRunningHostedUnitTests {
            // Run development-store repairs exactly once before RootView can read state.
            MainActor.assumeIsolated {
                AppPersistenceMigrationRunner.run(in: modelContainer.mainContext)
                try? OpeningFamiliarityCoordinator.runLifecyclePass(in: modelContainer.mainContext)
            }

            let posthogAPIKey = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String ?? ""
            let posthogHost = Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String ?? ""
            #if DEBUG
            if posthogAPIKey.isEmpty {
                assertionFailure("PostHogAPIKey variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once PostHogAPIKey is configured")
            }
            if posthogHost.isEmpty {
                assertionFailure("PostHogHost variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once PostHogHost is configured")
            }
            #endif
            if !posthogAPIKey.isEmpty, !posthogHost.isEmpty {
                let config = PostHogConfig(projectToken: posthogAPIKey, host: posthogHost)
                config.captureApplicationLifecycleEvents = true
                config.errorTrackingConfig.autoCapture = true
                config.sessionReplay = true
                #if DEBUG
                config.debug = true
                #endif
                PostHogSDK.shared.setup(config)
                ProductAnalyticsPreferences.syncPostHog()
            }
        }

        AppLanguageManager.apply(AppLanguageManager.persisted)

        if !isRunningHostedUnitTests {
            AppAudioSession.configureAmbient()

            let revenueCatAPIKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
            if !revenueCatAPIKey.isEmpty, revenueCatAPIKey != "appl_REPLACE_ME" {
                #if DEBUG
                Purchases.logLevel = .debug
                #endif
                Purchases.configure(withAPIKey: revenueCatAPIKey)
                MainActor.assumeIsolated {
                    Purchases.shared.delegate = ProEntitlementSyncDelegate.shared
                }
                Task { @MainActor in
                    await ProEntitlementSyncDelegate.shared.refreshFromServer()
                }
            }
        }

        UNUserNotificationCenter.current().delegate = BeforeShowNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(companionCoordinator)
                .environment(\.locale, languageController.language.locale)
                .onAppear {
                    guard !Self.isRunningHostedUnitTests else { return }
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                    appDelegate.noteDependenciesReady()
                }
                .task {
                    guard !Self.isRunningHostedUnitTests else { return }
                    isLocalMediaMaintenanceRunning = true
                    // Ensure delegate wiring even if onAppear ordering is delayed.
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                    appDelegate.noteDependenciesReady()
                    await companionCoordinator.refreshAllLinkedShows(in: modelContainer.mainContext)
                    await retryPendingShowAssetCleanupIfNeeded(in: modelContainer.mainContext)
                    await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: true)
                    await reconcileAllShowAssets(in: modelContainer.mainContext)
                    await reconcileAllDynamicCovers(
                        in: modelContainer.mainContext,
                        includesStagingCleanup: true
                    )
                    lastLocalMediaMaintenanceAt = Date()
                    isLocalMediaMaintenanceRunning = false
                    await LocalNotificationCenter.shared.reconcilePortfolio(
                        reason: .startup,
                        in: modelContainer.mainContext
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard !Self.isRunningHostedUnitTests else { return }
                    guard newPhase == .active else { return }
                    let shouldRunMediaMaintenance = ForegroundMediaMaintenancePolicy.shouldRun(
                        lastRun: lastLocalMediaMaintenanceAt,
                        isRunning: isLocalMediaMaintenanceRunning
                    )
                    if shouldRunMediaMaintenance {
                        isLocalMediaMaintenanceRunning = true
                    }
                    Task {
                        try? OpeningFamiliarityCoordinator.runLifecyclePass(in: modelContainer.mainContext)
                        await companionCoordinator.refreshAllLinkedShows(in: modelContainer.mainContext)
                        if shouldRunMediaMaintenance {
                            await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: false)
                            await reconcileAllShowAssets(in: modelContainer.mainContext)
                            await reconcileAllDynamicCovers(
                                in: modelContainer.mainContext,
                                includesStagingCleanup: false
                            )
                            lastLocalMediaMaintenanceAt = Date()
                            isLocalMediaMaintenanceRunning = false
                        }
                        await LocalNotificationCenter.shared.reconcilePortfolio(
                            reason: .foreground,
                            in: modelContainer.mainContext
                        )
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
