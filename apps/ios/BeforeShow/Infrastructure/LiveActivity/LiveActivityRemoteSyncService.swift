import Foundation
import UserNotifications

// MARK: - Live Activity Remote Plan Sync (ADR 0044 & Issue #358)

struct LiveActivitySyncRequest: Encodable, Sendable {
    var appInstanceId: String
    var appSignature: String
    var planSecret: String
    var plan: LiveActivityBoundedTransitionPlan
}

struct LiveActivitySyncResponse: Decodable, Sendable {
    var ok: Bool
    var acceptedVersion: Int?
    var planID: String?
}

struct LiveActivityRevokeRequest: Encodable, Sendable {
    var appInstanceId: String
    var appSignature: String
    var showID: String
    var planSecret: String
}

struct LiveActivityRevokeResponse: Decodable, Sendable {
    var ok: Bool
    var revoked: Bool?
}

actor LiveActivityRemoteSyncService {
    private let client: BeforeShowCloudClient
    private let ledger: LiveActivityReminderLedger
    private let secretProvider: @Sendable () -> String
    private let notificationRevoker: @Sendable (String) async -> Void
    private let notificationRestorer: (@Sendable ([PerformanceReminderEventKey]) async -> Void)?

    init(
        client: BeforeShowCloudClient,
        ledger: LiveActivityReminderLedger = .shared,
        secretProvider: @escaping @Sendable () -> String = { LiveActivityPlanSecretStore.current() },
        notificationRevoker: @escaping @Sendable (String) async -> Void = { identifier in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        },
        notificationRestorer: (@Sendable ([PerformanceReminderEventKey]) async -> Void)? = nil
    ) {
        self.client = client
        self.ledger = ledger
        self.secretProvider = secretProvider
        self.notificationRevoker = notificationRevoker
        self.notificationRestorer = notificationRestorer
    }

    /// 同步计划至云端；服务端接受后，将未来触发点前的事件从本地通知通道交接至实时活动通道。
    @discardableResult
    func syncPlan(
        _ plan: LiveActivityBoundedTransitionPlan,
        now: Date = Date()
    ) async -> Bool {
        let secret = secretProvider()
        guard !secret.isEmpty else { return false }

        let request = LiveActivitySyncRequest(
            appInstanceId: client.credentials.appInstanceId,
            appSignature: client.credentials.appSignature,
            planSecret: secret,
            plan: plan
        )

        do {
            let data = try await client.postJSON(path: "syncLiveActivityPlan", body: request)
            let response = try JSONDecoder().decode(LiveActivitySyncResponse.self, from: data)
            guard response.ok, response.acceptedVersion == plan.version else {
                return false
            }

            // 服务端已接受该计划版本，逐个尝试完成交接
            for step in plan.steps where step.state.isReminderActive {
                let events = step.reminderEvents ?? (step.state.reminderPerformanceIDs ?? []).map {
                    LiveActivityReminderEvent(performanceID: $0,
                        startsAt: step.state.reminderStartsAt ?? step.scheduledAt)
                }
                for event in events {
                    let eventKey = PerformanceReminderEventKey(
                        showID: plan.showID, performanceID: event.performanceID,
                        scheduledStartsAt: event.startsAt
                    )
                    let didHandover = await ledger.completeHandover(
                        eventKey: eventKey,
                        planVersion: plan.version,
                        now: now
                    )
                    if didHandover {
                        // 交接成功：撤除本地待发通知，避免双重打扰
                        await notificationRevoker(eventKey.notificationIdentifier)
                    }
                }
            }
            return true
        } catch {
            // 网络失败或服务端异常：保持本地通知兜底
            return false
        }
    }

    /// 现场结束、取消或撤销时，通知服务端停止投递，并将已交接且未到期的事件交回本地通知通道。
    @discardableResult
    func revokePlan(
        showID: String,
        now: Date = Date()
    ) async -> Bool {
        let handedOverRecords = await ledger.allRecords().filter {
            $0.eventKey.showID == showID && $0.status == .handedOver
        }
        var restoredKeys: [PerformanceReminderEventKey] = []
        for record in handedOverRecords {
            let didRevoke = await ledger.revokeToLocal(eventKey: record.eventKey, now: now)
            if didRevoke {
                restoredKeys.append(record.eventKey)
            }
        }
        if !restoredKeys.isEmpty, let notificationRestorer {
            await notificationRestorer(restoredKeys)
        }

        let secret = secretProvider()
        guard !secret.isEmpty else { return false }

        let request = LiveActivityRevokeRequest(
            appInstanceId: client.credentials.appInstanceId,
            appSignature: client.credentials.appSignature,
            showID: showID,
            planSecret: secret
        )

        do {
            let data = try await client.postJSON(path: "revokeLiveActivityPlan", body: request)
            let response = try JSONDecoder().decode(LiveActivityRevokeResponse.self, from: data)
            return response.ok
        } catch {
            return false
        }
    }
}


extension LiveActivityRemoteSyncService {
    @MainActor
    static let live: LiveActivityRemoteSyncService = {
        LiveActivityRemoteSyncService(
            client: BeforeShowCloudClient.production()
        )
    }()
}
