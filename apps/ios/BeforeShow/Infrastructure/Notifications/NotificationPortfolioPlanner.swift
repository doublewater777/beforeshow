import Foundation

struct NotificationPortfolioPlan {
    static let maximumScheduledRequests = 56

    let scheduledRequests: [ScheduledShowNotification]
    let retainedShowDayRequests: [ScheduledShowNotification]

    var modelRequests: [ScheduledShowNotification] {
        var byIdentifier = Dictionary(
            uniqueKeysWithValues: scheduledRequests.map { ($0.requestIdentifier, $0) }
        )
        for request in retainedShowDayRequests where byIdentifier[request.requestIdentifier] == nil {
            byIdentifier[request.requestIdentifier] = request
        }
        return Array(byIdentifier.values)
    }
}

/// 通知只给当前现场排；其他有确定日期的现场只排「开场前 3 小时」那条（ADR 0037）。
struct NotificationPortfolioPlanner {
    let scheduler: LocalNotificationScheduler

    init(calendar: Calendar = .current) {
        self.scheduler = LocalNotificationScheduler(calendar: calendar)
    }

    func plan(
        shows: [Show],
        existingRecords: [ShowNotificationScheduleRecord],
        currentShowID: UUID?,
        recommendations: FeatureRecommendationSnapshot? = nil,
        now: Date = Date()
    ) -> NotificationPortfolioPlan {
        let eligibleShows = shows.filter(Self.isEligibleForPortfolio)

        var naturalRequests: [ScheduledShowNotification] = []
        var retainedShowDayRequests: [ScheduledShowNotification] = []
        for show in eligibleShows {
            let start = CurrentShowTimeState(show: show, calendar: scheduler.calendar, now: now).effectiveStartTime
            let previous = existingRecords.filter {
                $0.showID == show.id && $0.milestone == .showDay && $0.isBackfill != true
                    && $0.showStartTime != nil && $0.showStartTime == start
            }.min { $0.fireDate < $1.fireDate }

            let scope: NotificationScheduleScope
            if show.id == currentShowID {
                let next = FeatureRecommendationLedger.nextFutureShow(excluding: show.id, in: shows, now: now)
                scope = NotificationScheduleScope(
                    includesAllMilestones: true,
                    recommendations: recommendations?.context(for: show.id) ?? FeatureRecommendationContext(),
                    nextShow: next.map { NotificationNextShow(show: $0, now: now) }
                )
            } else {
                scope = .showDayOnly
            }

            let requests = scheduler.futureRequests(
                for: show, now: now, scheduledShowDayFireDate: previous?.fireDate, scope: scope
            )
            naturalRequests.append(contentsOf: requests)
            if let reminder = requests.first(where: { $0.milestone == .showDay }) {
                retainedShowDayRequests.append(reminder)
            } else if let previous, let start, now < start {
                // Keep a due reminder as a completion marker until opening so another
                // foreground reconciliation cannot mint a fresh now + 10 minute reminder.
                retainedShowDayRequests.append(ScheduledShowNotification(
                    showID: show.id, milestone: .showDay, fireDate: previous.fireDate,
                    title: previous.title ?? "", body: previous.body ?? "", showStartTime: start,
                    destination: previous.destination ?? .route
                ))
            }
        }

        naturalRequests = Self.deduplicated(naturalRequests)

        let allCandidates = Self.sortedForScheduling(naturalRequests)
        let scheduled = Array(allCandidates.prefix(NotificationPortfolioPlan.maximumScheduledRequests))

        return NotificationPortfolioPlan(
            scheduledRequests: scheduled,
            retainedShowDayRequests: retainedShowDayRequests
        )
    }

    private static func isEligibleForPortfolio(_ show: Show) -> Bool {
        guard show.wasAddedAsHistorical != true,
              show.changeStatus != .canceled else {
            return false
        }
        if show.changeStatus == .postponed, show.postponedDate == nil {
            return false
        }
        return true
    }

    private static func deduplicated(
        _ requests: [ScheduledShowNotification]
    ) -> [ScheduledShowNotification] {
        var seen = Set<String>()
        return requests.filter { seen.insert($0.requestIdentifier).inserted }
    }

    private static func sortedForScheduling(
        _ requests: [ScheduledShowNotification]
    ) -> [ScheduledShowNotification] {
        requests.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            if lhs.milestone.portfolioPriority != rhs.milestone.portfolioPriority {
                return lhs.milestone.portfolioPriority < rhs.milestone.portfolioPriority
            }
            if lhs.showID != rhs.showID {
                return lhs.showID.uuidString < rhs.showID.uuidString
            }
            return lhs.requestIdentifier < rhs.requestIdentifier
        }
    }
}
