import Foundation
import SwiftData
import UserNotifications

@MainActor
enum NotificationSchedulingStateStore {
    static func canonicalize(in modelContext: ModelContext) throws -> NotificationSchedulingState {
        let states = try modelContext.fetch(FetchDescriptor<NotificationSchedulingState>())
            .sorted(by: canonicalOrder)
        let canonical: NotificationSchedulingState
        if let existing = states.first {
            canonical = existing
        } else {
            canonical = NotificationSchedulingState()
            modelContext.insert(canonical)
        }

        if states.count > 1 {
            canonical.hasRequestedPermissionAfterFirstShow = states.contains {
                $0.hasRequestedPermissionAfterFirstShow
            }
            canonical.backfillMintedShowIDs = Array(
                Set(states.flatMap { $0.backfillMintedShowIDs ?? [] })
            )
            canonical.portfolioMigrationVersion = states
                .compactMap(\.portfolioMigrationVersion)
                .max()
            for duplicate in states.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
        return canonical
    }

    private static func canonicalOrder(
        _ lhs: NotificationSchedulingState,
        _ rhs: NotificationSchedulingState
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct NotificationPortfolioRecordNormalization {
    let canonicalByIdentifier: [String: ShowNotificationScheduleRecord]
    let duplicates: [ShowNotificationScheduleRecord]
}

enum NotificationPortfolioRecordStore {
    static func normalize(
        records: [ShowNotificationScheduleRecord],
        modelRequests: [ScheduledShowNotification]
    ) -> NotificationPortfolioRecordNormalization {
        let desired = Dictionary(
            uniqueKeysWithValues: modelRequests.map { ($0.requestIdentifier, $0) }
        )
        let grouped = Dictionary(grouping: records, by: \.requestIdentifier)
        var canonical: [String: ShowNotificationScheduleRecord] = [:]
        var duplicates: [ShowNotificationScheduleRecord] = []

        for (identifier, candidates) in grouped {
            let expected = desired[identifier]
            let sorted = candidates.sorted { lhs, rhs in
                let lhsMatches = expected.map(lhs.matches) ?? false
                let rhsMatches = expected.map(rhs.matches) ?? false
                if lhsMatches != rhsMatches { return lhsMatches && !rhsMatches }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            if let keeper = sorted.first {
                canonical[identifier] = keeper
                duplicates.append(contentsOf: sorted.dropFirst())
            }
        }

        return NotificationPortfolioRecordNormalization(
            canonicalByIdentifier: canonical,
            duplicates: duplicates
        )
    }
}

@MainActor
final class LocalNotificationCenter {
    static let shared = LocalNotificationCenter()

    private let center = UNUserNotificationCenter.current()
    private let planner = NotificationPortfolioPlanner()

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

    /// Reconciles all eligible shows as one notification portfolio. Current Show is
    /// intentionally absent from this API: notification timing is independent from
    /// the user's durable Current Show focus.
    @discardableResult
    func reconcilePortfolio(
        reason: NotificationReconcileReason,
        in context: ModelContext,
        now: Date = Date()
    ) async -> Bool {
        do {
            let shows = try context.fetch(FetchDescriptor<Show>())
            let records = try context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())
            let schedulingState = try NotificationSchedulingStateStore.canonicalize(in: context)

            // A non-nil legacy field after portfolio migration means Add Show saved
            // successfully but the app exited before its backfill hand-off reconciled.
            let effectiveReason: NotificationReconcileReason
            if case .showAddedCandidate = reason {
                effectiveReason = reason
            } else if schedulingState.portfolioMigrationVersion == 1,
                      let stagedShowID = schedulingState.focusedShowID {
                effectiveReason = .showAddedCandidate(stagedShowID)
            } else {
                effectiveReason = reason
            }

            let plan = planner.plan(
                shows: shows,
                existingRecords: records,
                schedulingState: schedulingState,
                reason: effectiveReason,
                now: now
            )
            let normalization = NotificationPortfolioRecordStore.normalize(
                records: records,
                modelRequests: plan.modelRequests
            )

            for duplicate in normalization.duplicates {
                context.delete(duplicate)
            }

            let pendingIdentifiers = Set(
                await center.pendingNotificationRequests().map(\.identifier)
            )
            let scheduledByIdentifier = Dictionary(
                uniqueKeysWithValues: plan.scheduledRequests.map { ($0.requestIdentifier, $0) }
            )
            let modelByIdentifier = Dictionary(
                uniqueKeysWithValues: plan.modelRequests.map { ($0.requestIdentifier, $0) }
            )
            let scheduledIdentifiers = Set(scheduledByIdentifier.keys)
            let modelIdentifiers = Set(modelByIdentifier.keys)

            let staleRecords = normalization.canonicalByIdentifier.filter {
                !modelIdentifiers.contains($0.key)
            }
            let staleIdentifiers = staleRecords.map(\.key)
            if !staleIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
            }
            for (_, record) in staleRecords {
                context.delete(record)
            }

            var identifiersNeedingSystemWrite = Set<String>()
            for identifier in scheduledIdentifiers {
                guard let request = scheduledByIdentifier[identifier] else { continue }
                let existing = normalization.canonicalByIdentifier[identifier]
                if existing == nil
                    || existing?.matches(request) != true
                    || !pendingIdentifiers.contains(identifier) {
                    identifiersNeedingSystemWrite.insert(identifier)
                }
            }

            for identifier in modelIdentifiers {
                guard let request = modelByIdentifier[identifier] else { continue }
                if let existing = normalization.canonicalByIdentifier[identifier] {
                    if !existing.matches(request) {
                        existing.apply(request)
                    }
                } else {
                    context.insert(Self.makeRecord(from: request))
                }
            }

            // Retained backfills outside the 56-request system portfolio stay in
            // SwiftData with their minted timing/copy and can be scheduled later.
            let deferredIdentifiers = modelIdentifiers.subtracting(scheduledIdentifiers)
            let deferredPending = deferredIdentifiers.intersection(pendingIdentifiers)
            if !deferredPending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(deferredPending))
            }

            var didScheduleEveryRequest = true
            for identifier in identifiersNeedingSystemWrite.sorted() {
                guard let request = scheduledByIdentifier[identifier] else { continue }
                do {
                    try await center.add(request.makeNotificationRequest())
                } catch {
                    didScheduleEveryRequest = false
                }
            }

            for showID in plan.backfillShowIDsToMarkMinted {
                schedulingState.markBackfillMinted(showID: showID)
            }
            schedulingState.clearStagedBackfillCandidate()

            try context.save()
            return didScheduleEveryRequest
        } catch {
            context.rollback()
            return false
        }
    }

    /// Compatibility hand-off for the existing Add Show flow. `show` is not a focus;
    /// it is only the just-added show that may mint anticipation backfill once.
    @discardableResult
    func applyFocusChange(
        to show: Show?,
        in context: ModelContext,
        now: Date = Date()
    ) async -> Bool {
        await reconcilePortfolio(
            reason: show.map { .showAddedCandidate($0.id) } ?? .mutation,
            in: context,
            now: now
        )
    }

    /// Compatibility wrapper for existing foreground/settings call sites.
    @discardableResult
    func reconcileFocus(
        to _: Show?,
        in context: ModelContext,
        now: Date = Date()
    ) async -> Bool {
        await reconcilePortfolio(reason: .foreground, in: context, now: now)
    }

    private static func makeRecord(
        from request: ScheduledShowNotification
    ) -> ShowNotificationScheduleRecord {
        ShowNotificationScheduleRecord(
            showID: request.showID,
            milestone: request.milestone,
            fireDate: request.fireDate,
            isBackfill: request.isBackfill,
            title: request.title,
            body: request.body
        )
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
