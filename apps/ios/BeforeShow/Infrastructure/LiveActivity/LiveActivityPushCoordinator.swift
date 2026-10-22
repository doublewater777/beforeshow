import Foundation

// MARK: - Live Activity Push Coordinator (Issue #358 & ADR 0044)

actor LiveActivityPushCoordinator {
    static let shared = LiveActivityPushCoordinator()

    private let customSyncService: LiveActivityRemoteSyncService?
    private var lazyResolvedSyncService: LiveActivityRemoteSyncService?
    private var latestPushTokens: [String: String] = [:]
    private var currentSnapshot: WidgetShowSnapshot?
    private var focusedPerformanceID: UUID?
    private let appInstanceIDProvider: (@Sendable () async -> String)?

    init(
        syncService: LiveActivityRemoteSyncService? = nil,
        appInstanceIDProvider: (@Sendable () async -> String)? = nil
    ) {
        self.customSyncService = syncService
        self.appInstanceIDProvider = appInstanceIDProvider
    }

    private func resolveSyncService() async -> LiveActivityRemoteSyncService {
        if let custom = customSyncService { return custom }
        if let resolved = lazyResolvedSyncService { return resolved }
        let client = await MainActor.run { BeforeShowCloudClient.production() }
        let service = LiveActivityRemoteSyncService(client: client)
        self.lazyResolvedSyncService = service
        return service
    }

    /// 更新当前现场快照，并在有可用 token 时更新计划
    func updateSnapshot(_ snapshot: WidgetShowSnapshot?, focusedPerformanceID: UUID? = nil) async {
        self.currentSnapshot = snapshot
        self.focusedPerformanceID = focusedPerformanceID
        guard let snapshot else { return }
        let showID = snapshot.showID.uuidString
        if let token = latestPushTokens[showID] {
            await syncCurrentPlan(for: showID, pushToken: token)
        }
    }

    /// 处理获取到的 Token 并上报计划
    func handleTokenUpdate(_ token: String, for showID: String) async {
        latestPushTokens[showID] = token
        await syncCurrentPlan(for: showID, pushToken: token)
    }

    /// 撤销并注销指定现场的推送计划
    func revoke(showID: String) async {
        latestPushTokens.removeValue(forKey: showID)
        let service = await resolveSyncService()
        await service.revokePlan(showID: showID)
    }

    private func syncCurrentPlan(for showID: String, pushToken: String) async {
        guard let snapshot = currentSnapshot, snapshot.showID.uuidString == showID else { return }
        let focus = focusedPerformanceID
        let versionKey = "com.doublewaterapps.beforeshow.liveActivityPlanVersion.\(showID)"
        // Reserve before suspension: a lost response or restart must never reuse a version.
        // The timestamp floor also supersedes plans uploaded before versions were persisted.
        let nextVersion = max(
            UserDefaults.standard.integer(forKey: versionKey) + 1,
            Int(Date().timeIntervalSince1970 * 1_000)
        )
        UserDefaults.standard.set(nextVersion, forKey: versionKey)

        let isProduction: Bool
        #if DEBUG
        isProduction = false
        #else
        isProduction = true
        #endif

        let appInstanceID: String
        if let provider = appInstanceIDProvider {
            appInstanceID = await provider()
        } else {
            appInstanceID = await MainActor.run { BeforeShowCloudClient.productionAppInstanceId() }
        }

        guard currentSnapshot?.isContentEqual(to: snapshot) == true,
              focus == focusedPerformanceID, latestPushTokens[showID] == pushToken else { return }
        guard let plan = LiveActivityTransitionPlanBuilder.buildPlan(
            snapshot: snapshot,
            now: Date(),
            appInstanceID: appInstanceID,
            activityPushToken: pushToken,
            isProduction: isProduction,
            version: nextVersion,
            coverFilename: WidgetCoverCache.freshLiveActivityCoverFilename(for: snapshot.coverImageURL ?? ""),
            focusedPerformanceID: focus,
            artistImageFilename: WidgetCoverCache.freshLiveActivityCoverFilename(for:)
        ) else {
            return
        }

        let service = await resolveSyncService()
        await service.syncPlan(plan)
    }
}
