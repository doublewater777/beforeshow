import Foundation
import SwiftData
import UserNotifications

// MARK: - Notification Center

@MainActor
final class LocalNotificationCenter {
    static let shared = LocalNotificationCenter()

    private let center = UNUserNotificationCenter.current()
    private let scheduler = LocalNotificationScheduler()

    private init() {}

    func authorizationState() async -> NotificationAuthorizationState {
        NotificationAuthorizationState(await center.notificationSettings().authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Cancel everything tied to the previous focus and schedule the new current show.
    /// Missed natural milestones are never backfilled here by `planFocusChange`; the
    /// anticipation backfill below is minted separately, once per show.
    @discardableResult
    func applyFocusChange(to show: Show?, in context: ModelContext, now: Date = Date()) async -> Bool {
        let existingRecords = (try? context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())) ?? []
        let allShows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        // 已确认散场的现场即使让出焦点，它的 afterShow 也要继续排。
        let endedShows = allShows.filter { $0.endedAt != nil }
        let plan = scheduler.planFocusChange(
            from: existingRecords,
            to: show,
            preservingAfterShowOf: endedShows,
            now: now
        )
        var didScheduleEveryRequest = true

        var requestsToSchedule = plan.requestsToSchedule

        // 待发的补发不随重排丢弃：按记录原样重建（时刻和文案都是 mint 时定的，
        // 重算会得到另一组）。已删除现场的补发不再续命；已触发的（fireDate <= now）
        // 不重建，记录随下面的 recordsToCancel 清理。
        let liveShowIDs = Set(allShows.map(\.id))
        let rebuiltBackfill = existingRecords
            .filter { $0.isBackfill == true && $0.fireDate > now && liveShowIDs.contains($0.showID) }
            .map {
                ScheduledShowNotification(
                    showID: $0.showID,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: $0.title ?? "",
                    body: $0.body ?? "",
                    isBackfill: true
                )
            }
        requestsToSchedule.append(contentsOf: rebuiltBackfill)

        // 过期期待节点的补发：只在现场从未 mint 过时生成，mint 完登记。
        // 之后任何重排（编辑、切焦点、reconcile 对齐）都不会再来一轮——
        // 补发是添加时刻的情绪曲线重放，重复发送比不发更糟糕。
        if let show {
            let state = (try? context.fetch(FetchDescriptor<NotificationSchedulingState>()))?.first
            let schedulingState: NotificationSchedulingState
            if let state {
                schedulingState = state
            } else {
                schedulingState = NotificationSchedulingState()
                context.insert(schedulingState)
            }
            if !schedulingState.hasMintedBackfill(for: show.id) {
                let backfill = scheduler.backfillRequests(for: show, now: now)
                requestsToSchedule.append(contentsOf: backfill)
                schedulingState.markBackfillMinted(showID: show.id)
            }
        }

        let identifiersToCancel = plan.recordsToCancel.map(\.requestIdentifier)
        if !identifiersToCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        }
        for record in plan.recordsToCancel {
            context.delete(record)
        }

        for request in requestsToSchedule {
            let record = ShowNotificationScheduleRecord(
                showID: request.showID,
                milestone: request.milestone,
                fireDate: request.fireDate,
                isBackfill: request.isBackfill,
                title: request.title,
                body: request.body
            )
            context.insert(record)
            do {
                try await center.add(request.makeNotificationRequest())
            } catch {
                didScheduleEveryRequest = false
                context.delete(record)
            }
        }

        do {
            try context.save()
            WeatherReminderScheduler.shared.scheduleNextBackgroundCheck(modelContext: context)
            return didScheduleEveryRequest
        } catch {
            center.removePendingNotificationRequests(
                withIdentifiers: requestsToSchedule.map(\.requestIdentifier)
            )
            context.rollback()
            return false
        }
    }

    /// Re-align scheduled notifications with the show that is *currently* in focus.
    ///
    /// `applyFocusChange` only runs on explicit data mutations, but the current show
    /// also changes as time passes: once a show leaves its retention window the next
    /// show becomes current on its own. Without this the new focus stays silent and
    /// the old focus keeps stale pending requests. Called on launch and on foreground.
    ///
    /// Idempotent: when the stored records already match the desired plan nothing is
    /// rewritten, so repeated foregrounding does not churn the notification center.
    @discardableResult
    func reconcileFocus(to show: Show?, in context: ModelContext, now: Date = Date()) async -> Bool {
        let existingRecords = (try? context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())) ?? []
        // 与 applyFocusChange 同一套期望集合：焦点现场的全量节点
        // + 已确认散场现场的 afterShow，两边不一致会导致每次回前台都重排。
        let endedShows = ((try? context.fetch(FetchDescriptor<Show>())) ?? [])
            .filter { $0.endedAt != nil && $0.id != show?.id }
        var desired = show.map { scheduler.futureRequests(for: $0, now: now) } ?? []
        for ended in endedShows {
            if let request = scheduler.afterShowRequest(for: ended, now: now),
               !desired.contains(where: { $0.requestIdentifier == request.requestIdentifier }) {
                desired.append(request)
            }
        }

        let pendingIdentifiers = Set(
            await center.pendingNotificationRequests().map(\.identifier)
        )

        // 已触发的补发是「完成的使命」，不是 drift：记录清掉即可，不该触发重排——
        // 否则第一条补发触发后，下一次 reconcile 会把待发的第 2/3 条取消重建。
        let firedBackfills = existingRecords.filter { $0.isBackfill == true && $0.fireDate <= now }
        if !firedBackfills.isEmpty {
            for record in firedBackfills {
                context.delete(record)
            }
            try? context.save()
        }
        let activeRecords = existingRecords.filter { !($0.isBackfill == true && $0.fireDate <= now) }

        let recordedIdentifiers = Set(activeRecords.map(\.requestIdentifier))
        // 待发的补发始终属于期望集合。它们不在自然排期里，但标识符与
        // applyFocusChange 按记录重建的请求一一对应，两边一致才不会反复重排。
        let desiredIdentifiers = Set(desired.map(\.requestIdentifier))
            .union(activeRecords.filter { $0.isBackfill == true }.map(\.requestIdentifier))

        // Records for a show that is no longer in focus, or milestones that dropped out.
        let hasStaleRecords = !recordedIdentifiers.subtracting(desiredIdentifiers).isEmpty
        // Milestones we should hold but that never reached the notification center
        // (e.g. scheduled while permission was denied, or lost on reinstall).
        let isMissingFromCenter = !desiredIdentifiers.subtracting(pendingIdentifiers).isEmpty

        guard hasStaleRecords || isMissingFromCenter else { return true }

        return await applyFocusChange(to: show, in: context, now: now)
    }

    #if DEBUG
    func printPendingRequests() async {
        let pending = await center.pendingNotificationRequests()
        print("[BeforeShow] Pending notification requests: \(pending.count)")
        for request in pending {
            let triggerDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            print("  • \(request.identifier) | \(request.content.title) / \(request.content.body) | fire: \(String(describing: triggerDate))")
        }
    }
    #endif
}
