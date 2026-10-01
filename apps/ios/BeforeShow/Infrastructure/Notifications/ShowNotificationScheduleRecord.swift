import Foundation
import SwiftData

@Model
final class ShowNotificationScheduleRecord {
    var id: UUID
    var showID: UUID
    var milestoneRawValue: String
    var fireDate: Date
    var isBackfill: Bool?
    var title: String?
    var body: String?
    var showStartTime: Date?
    var createdAt: Date

    var milestone: ShowNotificationMilestone {
        ShowNotificationMilestone(rawValue: milestoneRawValue) ?? .showDay
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        milestone: ShowNotificationMilestone,
        fireDate: Date,
        isBackfill: Bool = false,
        title: String = "",
        body: String = "",
        createdAt: Date = Date(),
        showStartTime: Date? = nil
    ) {
        self.id = id
        self.showID = showID
        self.milestoneRawValue = milestone.rawValue
        self.fireDate = fireDate
        self.isBackfill = isBackfill
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.showStartTime = showStartTime
    }

    func matches(_ request: ScheduledShowNotification) -> Bool {
        showID == request.showID
            && milestoneRawValue == request.milestone.rawValue
            && fireDate == request.fireDate
            && isBackfill != true
            && (title ?? "") == request.title
            && (body ?? "") == request.body
            && showStartTime == request.showStartTime
    }

    func apply(_ request: ScheduledShowNotification) {
        showID = request.showID
        milestoneRawValue = request.milestone.rawValue
        fireDate = request.fireDate
        isBackfill = false
        title = request.title
        body = request.body
        showStartTime = request.showStartTime
    }
}
