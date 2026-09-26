import AVFoundation
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
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @StateObject private var languageController = AppLanguageController.shared
    @State private var companionCoordinator = CompanionSharingCoordinator()
    @State private var lastLocalMediaMaintenanceAt: Date?
    @State private var isLocalMediaMaintenanceRunning = false

    private let modelContainer: ModelContainer

    private static var isRunningHostedUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCInjectBundleInto"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundleInjectPath"] != nil
            || environment["DYLD_INSERT_LIBRARIES"]?.contains("libXCTestBundleInject.dylib") == true
            || ProcessInfo.processInfo.arguments.contains { $0.contains("XCTest") }
            || NSClassFromString("XCTestCase") != nil
    }

    init() {
        MainActor.assumeIsolated {
            // iOS 26 AVFoundation Observation must be enabled before any AVPlayer
            // instance is created. Preview playback then participates in the same
            // event-driven transport architecture as MusicKit.
            AVPlayer.isObservationEnabled = true
        }

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
                synchronizeFreeShowCapacity(in: modelContainer.mainContext)
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
            if Self.isRunningHostedUnitTests {
                Color.clear
            } else {
                RootView()
                    .environment(companionCoordinator)
                    .environment(\.locale, languageController.language.locale)
                    .onAppear {
                        appDelegate.companionCoordinator = companionCoordinator
                        appDelegate.modelContainer = modelContainer
                        appDelegate.noteDependenciesReady()
                    }
                    .task {
                        // Ensure delegate wiring even if onAppear ordering is delayed.
                        appDelegate.companionCoordinator = companionCoordinator
                        appDelegate.modelContainer = modelContainer
                        appDelegate.noteDependenciesReady()

                        await Task.yield()
                        synchronizeFreeShowCapacity(
                            in: modelContainer.mainContext,
                            entitlement: ProEntitlementStorage.decode(entitlementRawValue)
                        )

                        isLocalMediaMaintenanceRunning = true
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
                    .onChange(of: entitlementRawValue) { _, rawValue in
                        synchronizeFreeShowCapacity(
                            in: modelContainer.mainContext,
                            entitlement: ProEntitlementStorage.decode(rawValue)
                        )
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        let shouldRunMediaMaintenance = ForegroundMediaMaintenancePolicy.shouldRun(
                            lastRun: lastLocalMediaMaintenanceAt,
                            isRunning: isLocalMediaMaintenanceRunning
                        )
                        if shouldRunMediaMaintenance {
                            isLocalMediaMaintenanceRunning = true
                        }
                        Task {
                            synchronizeFreeShowCapacity(
                                in: modelContainer.mainContext,
                                entitlement: ProEntitlementStorage.decode(entitlementRawValue)
                            )
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
        }
        .modelContainer(modelContainer)
    }
}
