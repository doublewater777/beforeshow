import Foundation

// MARK: - Live Activity Push Coordinator (Issue #358 & ADR 0044)

actor LiveActivityPushCoordinator {
    static let shared = LiveActivityPushCoordinator()

    private let customSyncService: LiveActivityRemoteSyncService?
    private var lazyResolvedSyncService: LiveActivityRemoteSyncService?
    private var latestPushTokens: [String: String] = [:]
    private var planVersions: [String: Int] = [:]
    private var currentSnapshot: WidgetShowSnapshot?
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
    func updateSnapshot(_ snapshot: WidgetShowSnapshot?) async {
        self.currentSnapshot = snapshot
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
        planVersions.removeValue(forKey: showID)
        let service = await resolveSyncService()
        await service.revokePlan(showID: showID)
    }

    func currentVersion(for showID: String) -> Int? {
        planVersions[showID]
    }

    private func syncCurrentPlan(for showID: String, pushToken: String) async {
        guard let snapshot = currentSnapshot, snapshot.showID.uuidString == showID else { return }
        let nextVersion = (planVersions[showID] ?? 0) + 1

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

        guard let plan = LiveActivityTransitionPlanBuilder.buildPlan(
            snapshot: snapshot,
            now: Date(),
            appInstanceID: appInstanceID,
            activityPushToken: pushToken,
            isProduction: isProduction,
            version: nextVersion,
            coverFilename: WidgetCoverCache.freshLiveActivityCoverFilename(for: snapshot.coverImageURL ?? "")
        ) else {
            return
        }

        let service = await resolveSyncService()
        let success = await service.syncPlan(plan)
        if success {
            planVersions[showID] = nextVersion
        }
    }
}
