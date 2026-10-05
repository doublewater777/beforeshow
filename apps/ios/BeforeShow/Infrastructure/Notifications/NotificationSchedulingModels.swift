import Foundation
import SwiftData
import UserNotifications

enum NotificationAuthorizationState: String, Codable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional

    var allowsDelivery: Bool {
        self == .authorized || self == .provisional
    }
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
    case addedFollowUp
    case fourteenDaysBefore
    case sevenDaysBefore
    case threeDaysBefore
    case oneDayBefore
    case showDayMorning
    case showDay
    case openingMemory
    case postShowRitual
    case afterShow
    case footprintArrival
    case interestedPerformance
}

extension ShowNotificationMilestone {
    /// 唯一会响铃并突破专注模式的：「开场前 3 小时」错过有真实后果。
    var isTimeSensitive: Bool {
        self == .showDay || self == .interestedPerformance
    }

    /// 刚散场的轻提醒不主动亮屏，留在通知中心。
    var isPassive: Bool {
        self == .postShowRitual
    }

    /// 功能推荐节点：没有可推荐的功能就不发。
    var recommendationSlot: FeatureRecommendationSlot? {
        switch self {
        case .addedFollowUp: return .addedFollowUp
        case .fourteenDaysBefore: return .fourteenDaysBefore
        case .sevenDaysBefore: return .sevenDaysBefore
        case .threeDaysBefore: return .threeDaysBefore
        default: return nil
        }
    }

    var portfolioPriority: Int {
        switch self {
        case .showDay: return 0
        case .interestedPerformance: return 1
        case .openingMemory: return 2
        case .showDayMorning: return 2
        case .postShowRitual: return 3
        case .afterShow: return 4
        case .oneDayBefore: return 5
        case .footprintArrival: return 6
        case .threeDaysBefore: return 7
        case .sevenDaysBefore: return 8
        case .fourteenDaysBefore: return 9
        case .addedFollowUp: return 10
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
    /// 只有一位艺人时才说「去见」谁；多艺人或没有艺人时用现场本身。
    let artistName: String?
    let isFestival: Bool
    let place: String?
    let isMultiDay: Bool
    let startClock: String?

    init(show: Show, timeState: CurrentShowTimeState, calendar: Calendar) {
        let name = show.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.showName = name.isEmpty ? BSLocalization.text("这场现场") : name
        let artists = show.artistNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.artistName = artists.count == 1 ? artists[0] : nil
        self.isFestival = ShowFlavor.inferred(from: show) == .festival

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
    var destination: NotificationDeepLink.Destination = .home
    /// 推荐的功能；送达后计一次露出，用过后从通知中心撤掉。
    var feature: RecommendedFeature? = nil
    var performanceID: UUID? = nil
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
