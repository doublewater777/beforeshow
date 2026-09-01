import SwiftUI
import SwiftData
import UserNotifications
import PostHog
import RevenueCat

@main
struct BeforeShowApp: App {
    @UIApplicationDelegateAdaptor(BeforeShowAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var languageController = AppLanguageController.shared
    @State private var companionCoordinator = CompanionSharingCoordinator()
    @State private var lastLocalMediaMaintenanceAt: Date?
    @State private var isLocalMediaMaintenanceRunning = false

    private let modelContainer: ModelContainer = {
        // Companion sharing uses CloudKit CKRecord/CKShare APIs only.
        // Keep SwiftData local — do not mirror the whole store through CloudKit.
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: Show.self,
                CurrentShowSelection.self,
                NotificationSchedulingState.self,
                ShowNotificationScheduleRecord.self,
                MemoryFragment.self,
                MemoryMediaItem.self,
                ShowAsset.self,
                DynamicCover.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        // MARK: - PostHog
        // API key and host are embedded via Info.plist (injected from POSTHOG_API_KEY /
        // POSTHOG_HOST build settings in project.yml) so they ship in every build type,
        // including App Store and TestFlight, without any Xcode scheme dependency.
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

        AppLanguageManager.apply(AppLanguageManager.persisted)
        // Muted dynamic covers must never interrupt the user's music: the default
        // `soloAmbient` category stops other audio the moment an AVPlayer starts.
        AppAudioSession.configureAmbient()

        // MARK: - RevenueCat
        // 公共 SDK key 嵌入在 Info.plist（由 project.yml 的 REVENUECAT_API_KEY
        // 按 Debug/Release 注入）。Debug 走 Test Store；Release 需要 appl_ key。
        // 占位 / 缺失时静默跳过：defaultStore() 会回退到 Mock。
        let revenueCatAPIKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        if !revenueCatAPIKey.isEmpty, revenueCatAPIKey != "appl_REPLACE_ME" {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: revenueCatAPIKey)
            MainActor.assumeIsolated {
                Purchases.shared.delegate = ProEntitlementSyncDelegate.shared
            }
            // 启动后从服务端拉一次 entitlement，避免 paywall 看到陈旧的本地状态。
            Task { @MainActor in
                await ProEntitlementSyncDelegate.shared.refreshFromServer()
            }
        }

        UNUserNotificationCenter.current().delegate = BeforeShowNotificationDelegate.shared
        // 演出前一天天气提醒：注册 BG handler，handler 真正跑时另开 ModelContext 拿数据。
        WeatherReminderScheduler.shared.registerTaskHandler(modelContainer: modelContainer)
        // Wire CloudKit share acceptance dependencies before any scene callback can race.
        // RootView.onAppear is too late for cold-launch invitation acceptance.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(companionCoordinator)
                .environment(\.locale, languageController.language.locale)
                .onAppear {
                    // 在 noteDependenciesReady() 之前定格旧数据来源：它会立刻起
                    // Task flush 待处理邀请，可能把用户自己添加的现场翻成 participant 侧。
                                        ShowCreationOriginMigration.migrateIfNeeded(in: modelContainer.mainContext)
                    appDelegate.companionCoordinator = companionCoordinator
                    appDelegate.modelContainer = modelContainer
                    appDelegate.noteDependenciesReady()
                }
                .task {
                    // Mark the cold-launch maintenance in flight before the first await.
                    // The initial scenePhase=.active transition can now observe this and
                    // avoid launching a second full reconciliation concurrently.
                    isLocalMediaMaintenanceRunning = true

                                        ShowCreationOriginMigration.migrateIfNeeded(in: modelContainer.mainContext)
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
                    // 冷启动时也跑一次天气兜底：iOS 17 BG 唤醒不可靠。
                    await WeatherReminderScheduler.shared.runOpenCheck(
                        modelContext: modelContainer.mainContext
                    )
                    WeatherReminderScheduler.shared.scheduleNextBackgroundCheck(
                        modelContext: modelContainer.mainContext
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
                        await companionCoordinator.refreshAllLinkedShows(in: modelContainer.mainContext)
                        if shouldRunMediaMaintenance {
                            await reconcileAllMemoryMedia(in: modelContainer.mainContext, includesStagingCleanup: false)
                            await reconcileAllShowAssets(in: modelContainer.mainContext)
                            await reconcileAllDynamicCovers(
                                in: modelContainer.mainContext,
                                includesStagingCleanup: false
                            )
                            // Throttle from completion, not start, so a long-running
                            // maintenance pass still gets a full quiet window afterward.
                            lastLocalMediaMaintenanceAt = Date()
                            isLocalMediaMaintenanceRunning = false
                        }
                        // 回前台兜底：如果 BG 没跑，用户打开 App 也能收到天气提醒。
                        await WeatherReminderScheduler.shared.runOpenCheck(
                            modelContext: modelContainer.mainContext
                        )
                        WeatherReminderScheduler.shared.scheduleNextBackgroundCheck(
                            modelContext: modelContainer.mainContext
                        )
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
