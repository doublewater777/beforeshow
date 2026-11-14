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
    @State private var lastLocalMediaMaintenanceAt: Date?
    @State private var isLocalMediaMaintenanceRunning = false

    @State private var persistence: PersistenceStartup

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
            ListeningIntentBridge.handler = ListeningIntentHandler.shared
        }

        let isRunningHostedUnitTests = Self.isRunningHostedUnitTests

        let startup = PersistenceStartup.live()
        _persistence = State(initialValue: startup)
        if !isRunningHostedUnitTests {
            // Scheduled Live Activities can launch the process without a scene.
            // Open the store before returning so suspension cannot arrive while
            // SQLite still holds its lock.
            do {
                try startup.start()
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
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
                // 输入框全遮罩保留默认 true；但刻意关掉「全图遮罩」——封面、唱片、
                // 回忆卡片照片是核心视觉，全遮会让回放看不出用户在操作什么。
                // 用户照片改用 .bsMaskUserContent() 显式标记（见 BSUserContentMask）。
                config.sessionReplayConfig.maskAllImages = false
                #if DEBUG
                config.debug = true
                #endif
                PostHogSDK.shared.setup(config)
                ProductAnalyticsPreferences.syncPostHog()
                ProductAnalytics.identify()
            }
        }


        if !isRunningHostedUnitTests {
            AppAudioSession.applyPolicy()

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
            Group {
            if Self.isRunningHostedUnitTests {
                Color.clear
            } else if let modelContainer = persistence.container {
                RootView()
                    .modelContainer(modelContainer)
                    .task {
                        await Task.yield()
                        synchronizeFreeShowCapacity(
                            in: modelContainer.mainContext,
                            entitlement: ProEntitlementStorage.decode(entitlementRawValue)
                        )

                        isLocalMediaMaintenanceRunning = true
                        await MediaBackupInclusion.includeIfNeeded()
                        await retryPendingShowAssetCleanupIfNeeded(in: modelContainer.mainContext)
                        await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: true)
                        await reconcileAllShowAssets(in: modelContainer.mainContext)
                        lastLocalMediaMaintenanceAt = Date()
                        isLocalMediaMaintenanceRunning = false
                        await LocalNotificationCenter.shared.reconcilePortfolio(
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
                            if shouldRunMediaMaintenance {
                                await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: false)
                                await reconcileAllShowAssets(in: modelContainer.mainContext)
                                lastLocalMediaMaintenanceAt = Date()
                                isLocalMediaMaintenanceRunning = false
                            }
                            await LocalNotificationCenter.shared.reconcilePortfolio(
                                in: modelContainer.mainContext
                            )
                        }
                    }
            } else if persistence.needsRetry {
                Button("重试") { startPersistence() }
                    .task { startPersistence() }
            } else {
                ProgressView()
            }
            }
            .onOpenURL { url in
                if LegacyCompanionInviteInbox.shared.receive(url) || SharedShowInbox.shared.receive(url) {
                    return
                } else if url.scheme == "beforeshow", url.host == "listen" || url.host == "listening" {
                    ProductAnalytics.capture(.appOpenedFrom(source: .widget, destination: "listen", feature: nil))
                    NotificationDeepLinkRouter.shared.route(to: NotificationDeepLink(showID: UUID(), destination: .listen))
                } else if let deepLink = NotificationDeepLink(url: url) {
                    ProductAnalytics.capture(.appOpenedFrom(
                        source: .liveActivity, destination: deepLink.destination.rawValue, feature: nil
                    ))
                    NotificationDeepLinkRouter.shared.route(to: deepLink)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !Self.isRunningHostedUnitTests else { return }
                startPersistence()
            }
        }
    }

    @MainActor
    private func startPersistence() {
        do {
            try persistence.start()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
