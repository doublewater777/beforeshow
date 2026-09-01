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
}

enum ShowNotificationMilestone: String, CaseIterable, Codable, Equatable {
    case fourteenDaysBefore
    case sevenDaysBefore
    case threeDaysBefore
    case oneDayBefore
    /// 现场当天早上：交通、取票、周边留出时间。
    case showDayMorning
    /// 开场前 3 小时：唯一一条会打断用户的通知。
    case showDay
    /// 开场时刻：安静落到统一记忆编辑器。
    case openingMemory
    /// 散场次日上午：唯一一条非提醒性质的通知，落到记忆碎片。
    case afterShow
}

extension ShowNotificationMilestone {
    /// 只有「快开场了」带声音并突破专注模式——错过它有真实后果。
    /// 其余节点是普通横幅（无声音）。
    var isTimeSensitive: Bool {
        self == .showDay
    }

    /// 期待期四个节点：临近开场才添加现场时会被补发（见 backfillRequests）。
    /// showDay/openingMemory/afterShow 各有自己的兜底和生命周期，不参与补发。
    var isAnticipation: Bool {
        switch self {
        case .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore, .oneDayBefore:
            return true
        case .showDayMorning, .showDay, .openingMemory, .afterShow:
            return false
        }
    }
}

/// 现场类型。产品只支持演唱会 / Livehouse / 音乐节，但模型里没有类型字段，
/// 所以按名称和场馆推断，只用于挑选通知语气，推断错也不会影响任何数据。
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

/// 通知文案要用到的现场事实。抽出来是为了让文案函数保持纯函数、可单测，
/// 不必在每个分支里重复解包 optional 场馆 / 城市。
struct NotificationCopyContext {
    let showName: String
    let flavor: ShowFlavor
    /// 场馆优先，没有就退到城市，两者都没有则为 nil。
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
    /// 过期节点的补发：普通横幅（.active 无声音），文案按实际剩余天数重写。
    var isBackfill: Bool = false
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
    /// 已补发过过期节点的现场。每场现场只 mint 一次：补发是基于添加时刻
    /// 的情绪曲线重放，编辑 / 切焦点 / reconcile 重排都不该再来一轮。
    /// 存储层必须可选：旧数据没有这一列，非可选属性会让轻量迁移直接失败。
    var backfillMintedShowIDs: [UUID]?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        focusedShowID: UUID? = nil,
        hasRequestedPermissionAfterFirstShow: Bool = false,
        backfillMintedShowIDs: [UUID]? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.focusedShowID = focusedShowID
        self.hasRequestedPermissionAfterFirstShow = hasRequestedPermissionAfterFirstShow
        self.backfillMintedShowIDs = backfillMintedShowIDs
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

    func hasMintedBackfill(for showID: UUID) -> Bool {
        backfillMintedShowIDs?.contains(showID) ?? false
    }

    func markBackfillMinted(showID: UUID) {
        var ids = backfillMintedShowIDs ?? []
        if !ids.contains(showID) {
            ids.append(showID)
            backfillMintedShowIDs = ids
        }
        updatedAt = Date()
    }
}

@Model
final class ShowNotificationScheduleRecord {
    var id: UUID
    var showID: UUID
    var milestoneRawValue: String
    var fireDate: Date
    /// 补发记录自带文案：重排（applyFocusChange）时待发的补发要按记录原样重建，
    /// 不能靠 backfillRequests 重算（那会按新的 now 生成另一组时刻）。
    /// 存储层可选：旧数据没有这三列，非可选属性会让轻量迁移直接失败；
    /// 读取处按 `== true` / `?? ""` 处理，nil 即「自然节点记录」。
    var isBackfill: Bool?
    var title: String?
    var body: String?
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
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.milestoneRawValue = milestone.rawValue
        self.fireDate = fireDate
        self.isBackfill = isBackfill
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}
