import Foundation
import SwiftData

enum NotificationAuthorizationState: String, Codable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
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
}

enum ShowNotificationMilestone: String, CaseIterable, Codable, Equatable {
    case fourteenDaysBefore
    case oneDayBefore
    case showDay
}

struct ScheduledShowNotification: Equatable {
    let showID: UUID
    let milestone: ShowNotificationMilestone
    let fireDate: Date
    let title: String
    let body: String
}

struct NotificationReschedulePlan: Equatable {
    let recordsToCancel: [ShowNotificationScheduleRecord]
    let requestsToSchedule: [ScheduledShowNotification]
}

@Model
final class NotificationSchedulingState {
    var id: UUID
    var focusedShowID: UUID?
    var hasRequestedPermissionAfterFirstShow: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        focusedShowID: UUID? = nil,
        hasRequestedPermissionAfterFirstShow: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.focusedShowID = focusedShowID
        self.hasRequestedPermissionAfterFirstShow = hasRequestedPermissionAfterFirstShow
        self.updatedAt = updatedAt
    }

    func recordPermissionRequest() {
        hasRequestedPermissionAfterFirstShow = true
        updatedAt = Date()
    }

    func focus(showID: UUID?) {
        focusedShowID = showID
        updatedAt = Date()
    }
}

@Model
final class ShowNotificationScheduleRecord {
    var id: UUID
    var showID: UUID
    var milestoneRawValue: String
    var fireDate: Date
    var createdAt: Date

    var milestone: ShowNotificationMilestone {
        ShowNotificationMilestone(rawValue: milestoneRawValue) ?? .showDay
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        milestone: ShowNotificationMilestone,
        fireDate: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.milestoneRawValue = milestone.rawValue
        self.fireDate = fireDate
        self.createdAt = createdAt
    }
}

struct LocalNotificationScheduler {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func futureRequests(for show: Show, now: Date = Date()) -> [ScheduledShowNotification] {
        let timeState = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        return milestoneDates(for: timeState)
            .filter { $0.fireDate > now }
            .map {
                ScheduledShowNotification(
                    showID: show.id,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: notificationTitle(for: $0.milestone),
                    body: notificationBody(for: $0.milestone, showName: show.name)
                )
            }
    }

    func planFocusChange(
        from existingRecords: [ShowNotificationScheduleRecord],
        to newCurrentShow: Show?,
        now: Date = Date()
    ) -> NotificationReschedulePlan {
        let futureRecordsToCancel = existingRecords.filter { $0.fireDate > now }
        let requests = newCurrentShow.map { futureRequests(for: $0, now: now) } ?? []

        return NotificationReschedulePlan(
            recordsToCancel: futureRecordsToCancel,
            requestsToSchedule: requests
        )
    }

    private func milestoneDates(
        for timeState: CurrentShowTimeState
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        [
            (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20)),
            (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20)),
            (.showDay, showDayReminderDate(for: timeState))
        ].compactMap { milestone, fireDate in
            fireDate.map { (milestone, $0) }
        }
    }

    private func dayRelativeToShow(_ timeState: CurrentShowTimeState, offset: Int, hour: Int) -> Date? {
        let showDay = calendar.startOfDay(for: timeState.effectiveDate)
        guard let targetDay = calendar.date(byAdding: .day, value: offset, to: showDay) else {
            return nil
        }

        return calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: targetDay
        )
    }

    private func showDayReminderDate(for timeState: CurrentShowTimeState) -> Date? {
        if let startTime = timeState.effectiveStartTime {
            return calendar.date(byAdding: .hour, value: -3, to: startTime)
        }

        return calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: calendar.startOfDay(for: timeState.effectiveDate)
        )
    }

    private func notificationBody(for milestone: ShowNotificationMilestone, showName: String) -> String {
        switch milestone {
        case .fourteenDaysBefore:
            return "\(showName) 还有两周，开场之前，先进入状态。"
        case .oneDayBefore:
            return "\(showName) 明天见。"
        case .showDay:
            return "\(showName) 快开场了。"
        }
    }

    private func notificationTitle(for milestone: ShowNotificationMilestone) -> String {
        switch milestone {
        case .fourteenDaysBefore:
            return "开场之前，先进入状态"
        case .oneDayBefore:
            return "明天见"
        case .showDay:
            return "快开场了"
        }
    }
}
