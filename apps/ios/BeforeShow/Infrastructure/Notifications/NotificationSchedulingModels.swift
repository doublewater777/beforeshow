import Foundation
import SwiftData
import UserNotifications

enum NotificationAuthorizationState: String, Codable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

extension NotificationAuthorizationState {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
}

struct NotificationPermissionPolicy {
    func shouldRequestPermission(
        hasAddedShow: Bool,
        authorizationState: NotificationAuthorizationState,
        hasRequestedPermissionAfterFirstShow: Bool
    ) -> Bool {
        hasAddedShow
            && authorizationState == .notDetermined
            && !hasRequestedPermissionAfterFirstShow
    }

    func shouldRequestOnCurrentShow(
        authorizationState: NotificationAuthorizationState,
        hasRequestedPermissionAfterFirstShow: Bool,
        currentShowKind: CurrentShowTimeKind,
        isCurrentShowVisible: Bool
    ) -> Bool {
        guard isCurrentShowVisible,
              shouldRequestPermission(
                hasAddedShow: true,
                authorizationState: authorizationState,
                hasRequestedPermissionAfterFirstShow: hasRequestedPermissionAfterFirstShow
              ) else {
            return false
        }

        switch currentShowKind {
        case .before, .today, .dayEnded:
            return true
        case .postShow, .ended, .canceled, .postponed:
            return false
        }
    }
}

enum ShowNotificationMilestone: String, CaseIterable, Codable, Equatable {
    case fourteenDaysBefore
    case sevenDaysBefore
    case threeDaysBefore
    case oneDayBefore
    case showDayMorning
    case showDay
    case openingMemory
    case afterShow
}

extension ShowNotificationMilestone {
    var isTimeSensitive: Bool {
        self == .showDay
    }

    fileprivate var portfolioPriority: Int {
        switch self {
        case .showDay: return 0
        case .openingMemory: return 1
        case .showDayMorning: return 2
        case .afterShow: return 3
        case .oneDayBefore: return 4
        case .threeDaysBefore: return 5
        case .sevenDaysBefore: return 6
        case .fourteenDaysBefore: return 7
        }
    }
}

enum ShowFlavor {
    case festival
    case livehouse
    case concert

    static func inferred(from show: Show) -> ShowFlavor {
        let haystack = [show.name, show.venueName ?? ""]
            .joined(separator: " ")
            .lowercased()

        if haystack.contains("音乐节") || haystack.contains("festival")
            || haystack.contains("live house 音乐节") {
            return .festival
        }
        if haystack.contains("livehouse") || haystack.contains("live house")
            || haystack.contains("酒球会") || haystack.contains("club") {
            return .livehouse
        }
        return .concert
    }
}

struct NotificationCopyContext {
    let showName: String
    let flavor: ShowFlavor
    let place: String?
    let isMultiDay: Bool
    let startClock: String?

    init(show: Show, timeState: CurrentShowTimeState, calendar: Calendar) {
        self.showName = show.name
        self.flavor = ShowFlavor.inferred(from: show)

        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let venue, !venue.isEmpty {
            self.place = venue
        } else if let city, !city.isEmpty {
            self.place = city
        } else {
            self.place = nil
        }

        if let endDate = timeState.effectiveEndDate {
            self.isMultiDay = calendar.startOfDay(for: endDate) > calendar.startOfDay(for: timeState.effectiveDate)
        } else {
            self.isMultiDay = false
        }

        if let start = timeState.effectiveStartTime {
            self.startClock = String(
                format: "%02d:%02d",
                calendar.component(.hour, from: start),
                calendar.component(.minute, from: start)
            )
        } else {
            self.startClock = nil
        }
    }
}

struct ScheduledShowNotification: Equatable {
    let showID: UUID
    let milestone: ShowNotificationMilestone
    let fireDate: Date
    let title: String
    let body: String
    var showStartTime: Date? = nil
}

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

struct NotificationPortfolioPlanner {
    let scheduler: LocalNotificationScheduler

    init(calendar: Calendar = .current) {
        self.scheduler = LocalNotificationScheduler(calendar: calendar)
    }

    func plan(
        shows: [Show],
        existingRecords: [ShowNotificationScheduleRecord],
        now: Date = Date()
    ) -> NotificationPortfolioPlan {
        let eligibleShows = shows.filter(Self.isEligibleForPortfolio)

        var naturalRequests: [ScheduledShowNotification] = []
        var retainedShowDayRequests: [ScheduledShowNotification] = []
        for show in eligibleShows {
            if show.endedAt != nil {
                if let afterShow = scheduler.afterShowRequest(for: show, now: now) {
                    naturalRequests.append(afterShow)
                }
            } else {
                let start = CurrentShowTimeState(show: show, calendar: scheduler.calendar, now: now).effectiveStartTime
                let previous = existingRecords.filter {
                    $0.showID == show.id && $0.milestone == .showDay && $0.isBackfill != true
                        && $0.showStartTime != nil && $0.showStartTime == start
                }.min { $0.fireDate < $1.fireDate }
                let requests = scheduler.futureRequests(
                    for: show, now: now, scheduledShowDayFireDate: previous?.fireDate
                )
                naturalRequests.append(contentsOf: requests)
                if let reminder = requests.first(where: { $0.milestone == .showDay }) {
                    retainedShowDayRequests.append(reminder)
                } else if let previous, let start, now < start {
                    // Keep a due reminder as a completion marker until opening so another
                    // foreground reconciliation cannot mint a fresh now + 10 minute reminder.
                    retainedShowDayRequests.append(ScheduledShowNotification(
                        showID: show.id, milestone: .showDay, fireDate: previous.fireDate,
                        title: previous.title ?? "", body: previous.body ?? "", showStartTime: start
                    ))
                }
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

@Model
final class NotificationSchedulingState {
    var id: UUID
    var hasRequestedPermissionAfterFirstShow: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        hasRequestedPermissionAfterFirstShow: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hasRequestedPermissionAfterFirstShow = hasRequestedPermissionAfterFirstShow
        self.updatedAt = updatedAt
    }

    func recordPermissionRequest() {
        hasRequestedPermissionAfterFirstShow = true
        updatedAt = Date()
    }
}
