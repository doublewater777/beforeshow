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

struct LocalNotificationScheduler {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func futureRequests(for show: Show, now: Date = Date()) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        return milestoneDates(for: timeState, show: show, calendar: eventCalendar, now: now)
            .filter { $0.fireDate > now }
            .map {
                ScheduledShowNotification(
                    showID: show.id,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: notificationTitle(for: $0.milestone, context: context),
                    body: notificationBody(for: $0.milestone, context: context)
                )
            }
    }

    // MARK: - Backfill

    private static let maxBackfillCount = 3
    private static let firstBackfillDelay: TimeInterval = 60 * 60
    private static let backfillInterval: TimeInterval = 12 * 60 * 60
    private static let backfillCrowdingGap: TimeInterval = 4 * 60 * 60

    /// 临近开场才添加的现场，期待期节点已经错过。逐条补发、间隔铺开、封顶 3 条，
    /// 让晚添加的用户也能收到期待曲线，而不是干等下一个自然节点。
    ///
    /// 节奏：首条 1 小时后，之后每 12 小时一条；落在 22:00–08:00 的顺延到清醒时段。
    /// 防拥挤：与任一自然未来节点相距 <4h、或不早于开场时刻的槽位直接丢弃
    /// （残局由 showDay / openingMemory 覆盖）。
    ///
    /// 只在 applyFocusChange 里 mint（每场现场一次，见 backfillMintedShowIDs）；
    /// reconcile 不调用它——补发时刻依赖 mint 当时的 now，重算会得到另一组时刻。
    func backfillRequests(for show: Show, now: Date = Date()) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else { return [] }

        let milestones = milestoneDates(for: timeState, show: show, calendar: eventCalendar, now: now)
        // milestoneDates 按 14→7→3→1 的时间顺序产出，suffix 取最近错过的 3 条，
        // 重放时仍然沿着情绪曲线走。
        let missed = milestones
            .filter { $0.milestone.isAnticipation && $0.fireDate <= now }
            .suffix(Self.maxBackfillCount)
        guard !missed.isEmpty else { return [] }

        let naturalFireDates = milestones.filter { $0.fireDate > now }.map(\.fireDate)
        let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: eventCalendar)
        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        let showDay = eventCalendar.startOfDay(for: timeState.effectiveDate)

        // 槽位链式推进：每条在上一条（顺延后的）基础上 +12h，保证相邻补发
        // 至少隔半天；直接落在 22:00–08:00 的先顺延到清醒时段再入链。
        var requests: [ScheduledShowNotification] = []
        var nextSlot = wakingHoursAdjusted(
            now + Self.firstBackfillDelay,
            calendar: eventCalendar
        )
        for entry in missed {
            guard let slot = nextSlot else { break }
            nextSlot = wakingHoursAdjusted(
                slot + Self.backfillInterval,
                calendar: eventCalendar
            )
            // 不早于开场时刻的槽位丢弃；槽位只会越来越晚，可以直接收工。
            guard slot < showStart else { break }
            // 与自然未来节点相距 <4h 的槽位丢弃，避免两条挤在一起。
            guard !naturalFireDates.contains(where: {
                abs($0.timeIntervalSince(slot)) < Self.backfillCrowdingGap
            }) else { continue }

            // 文案按补发触发当天的实际剩余天数写，原节点文案里「还有 N 天」已经不准了。
            let slotDay = eventCalendar.startOfDay(for: slot)
            let days = eventCalendar.dateComponents([.day], from: slotDay, to: showDay).day ?? 0
            let copy = backfillCopy(daysRemaining: days, context: context)
            requests.append(ScheduledShowNotification(
                showID: show.id,
                milestone: entry.milestone,
                fireDate: slot,
                title: copy.title,
                body: copy.body,
                isBackfill: true
            ))
        }
        return requests
    }

    /// 深夜不打扰：22:00–08:00 的槽位顺延，<8 点到当天 08:00，≥22 点到次日 10:00。
    private func wakingHoursAdjusted(_ date: Date, calendar: Calendar) -> Date? {
        let hour = calendar.component(.hour, from: date)
        if hour < 8 {
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date)
        }
        if hour >= 22 {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay)
        }
        return date
    }

    /// 补发文案：触发当天就开场的复用「今天开场」；更早的用带实际剩余天数的
    /// 通用句（不复用「明天见」——临场前一天添加时会和当晚的自然节点文案撞车），
    /// 标题映射到最近的情绪节点。
    private func backfillCopy(
        daysRemaining: Int,
        context: NotificationCopyContext
    ) -> (title: String, body: String) {
        if daysRemaining <= 0 {
            return (
                notificationTitle(for: .showDayMorning, context: context),
                notificationBody(for: .showDayMorning, context: context)
            )
        }
        let bucket: ShowNotificationMilestone
        if daysRemaining >= 10 {
            bucket = .fourteenDaysBefore
        } else if daysRemaining >= 5 {
            bucket = .sevenDaysBefore
        } else if daysRemaining >= 2 {
            bucket = .threeDaysBefore
        } else {
            bucket = .oneDayBefore
        }
        return (
            notificationTitle(for: bucket, context: context),
            BSLocalization.format("%1$@ 还有 %2$d 天，已经开始期待了", context.showName, daysRemaining)
        )
    }

    func planFocusChange(
        from existingRecords: [ShowNotificationScheduleRecord],
        to newCurrentShow: Show?,
        preservingAfterShowOf endedShows: [Show] = [],
        now: Date = Date()
    ) -> NotificationReschedulePlan {
        var requests = newCurrentShow.map { futureRequests(for: $0, now: now) } ?? []

        // afterShow 属于已结束现场自身的生命周期，不随通知焦点切换取消——
        // 否则走「确认散场」主流程的用户永远收不到这条次日回看通知。
        for show in endedShows where show.id != newCurrentShow?.id {
            if let request = afterShowRequest(for: show, now: now),
               !requests.contains(where: { $0.requestIdentifier == request.requestIdentifier }) {
                requests.append(request)
            }
        }

        return NotificationReschedulePlan(
            recordsToCancel: existingRecords,
            requestsToSchedule: requests
        )
    }

    /// 已确认散场（endedAt != nil）的现场的「次日回看」请求。
    /// 只在未来触发时刻存在时返回；未确认散场的现场不由这里负责
    /// （它还握着通知焦点，afterShow 已含在 futureRequests 里）。
    func afterShowRequest(for show: Show, now: Date = Date()) -> ScheduledShowNotification? {
        guard show.endedAt != nil else { return nil }
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard let fireDate = afterShowReminderDate(for: timeState, calendar: eventCalendar, confirmedEnd: show.endedAt),
              fireDate > now else { return nil }
        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        return ScheduledShowNotification(
            showID: show.id,
            milestone: .afterShow,
            fireDate: fireDate,
            title: notificationTitle(for: .afterShow, context: context),
            body: notificationBody(for: .afterShow, context: context)
        )
    }

    private func milestoneDates(
        for timeState: CurrentShowTimeState,
        show: Show,
        calendar: Calendar,
        now: Date
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let planned: [(ShowNotificationMilestone, Date?)] = [
            (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20, calendar: calendar)),
            (.sevenDaysBefore, dayRelativeToShow(timeState, offset: -7, hour: 20, calendar: calendar)),
            (.threeDaysBefore, dayRelativeToShow(timeState, offset: -3, hour: 20, calendar: calendar)),
            (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20, calendar: calendar)),
            (.showDayMorning, dayRelativeToShow(timeState, offset: 0, hour: 9, calendar: calendar)),
            (.showDay, showDayReminderDate(for: timeState, calendar: calendar, now: now)),
            (
                .openingMemory,
                OpeningMemoryWindow.notificationFireDate(
                    now: now,
                    showStart: showStart,
                    hasConfirmedEnd: show.endedAt != nil
                )
            ),
            (.afterShow, afterShowReminderDate(for: timeState, calendar: calendar))
        ]

        return planned.compactMap { milestone, fireDate in
            fireDate.map { (milestone, $0) }
        }
    }

    private func dayRelativeToShow(
        _ timeState: CurrentShowTimeState,
        offset: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date? {
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

    /// 开场前 3 小时。临时添加的现场（3 小时内开场）不能因为节点已过就静默，
    /// 只要还没开场就顺延到 10 分钟后，保证至少收到一条。
    private func showDayReminderDate(
        for timeState: CurrentShowTimeState,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        guard let startTime = timeState.effectiveStartTime else {
            return calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: calendar.startOfDay(for: timeState.effectiveDate)
            )
        }

        guard let threeHoursBefore = calendar.date(byAdding: .hour, value: -3, to: startTime) else {
            return nil
        }
        if threeHoursBefore > now {
            return threeHoursBefore
        }
        // 已经进入开场前 3 小时窗口：还没开场就补一条，开场后不再补。
        guard now < startTime, let soon = calendar.date(byAdding: .minute, value: 10, to: now) else {
            return nil
        }
        return min(soon, startTime)
    }

    /// 散场次日 11:00。用户确认过散场就以真实散场时刻为准，否则按最后一天的估算边界。
    private func afterShowReminderDate(
        for timeState: CurrentShowTimeState,
        calendar: Calendar,
        confirmedEnd: Date? = nil
    ) -> Date? {
        let lastDay = calendar.startOfDay(
            for: confirmedEnd ?? timeState.effectiveEndDate ?? timeState.effectiveDate
        )
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        return calendar.date(bySettingHour: 11, minute: 0, second: 0, of: nextDay)
    }

    /// 情绪曲线：期待 → 想象 → 具体 → 收束 → 出门 → 紧迫 → 回看。
    /// 有场馆 / 城市时说得更具体，缺字段时退回通用句，不出现空占位。
    private func notificationBody(
        for milestone: ShowNotificationMilestone,
        context: NotificationCopyContext
    ) -> String {
        let name = context.showName

        switch milestone {
        case .fourteenDaysBefore:
            return BSLocalization.format("%@ 还有两周，期待已经开始了", name)

        case .sevenDaysBefore:
            if let place = context.place {
                return BSLocalization.format("%1$@ 还有一周，可以先查查 %2$@ 怎么去", name, place)
            }
            return BSLocalization.format("%@ 还有一周，可以先想想那天的样子了", name)

        case .threeDaysBefore:
            switch context.flavor {
            case .festival:
                return BSLocalization.format("%@ 还有三天，防晒、雨具和折叠椅可以先备好", name)
            case .livehouse:
                return BSLocalization.format("%@ 还有三天，站场时间不短，选一双好走的鞋", name)
            case .concert:
                return BSLocalization.format("%@ 还有三天，门票和身份证件先确认一遍", name)
            }

        case .oneDayBefore:
            if context.isMultiDay {
                return BSLocalization.format("%@ 明天开始，第一天的东西今晚就收好", name)
            }
            return BSLocalization.format("%@ 明天见，今晚早点休息", name)

        case .showDayMorning:
            if let place = context.place, let clock = context.startClock {
                return BSLocalization.format("今天 %1$@ 在 %2$@ 开场，路上和取票都留够时间", clock, place)
            }
            if let clock = context.startClock {
                return BSLocalization.format("今天 %1$@ 开场，%2$@ 的路上留够时间", clock, name)
            }
            return BSLocalization.format("今天就是 %@，出门前留够时间", name)

        case .showDay:
            if let place = context.place {
                return BSLocalization.format("%1$@ 快开场了，%2$@ 见", name, place)
            }
            return BSLocalization.format("%@ 快开场了，门票和手机电量再确认一遍", name)

        case .afterShow:
            return BSLocalization.format("%@ 的余温还在，想说的可以留在这里", name)

        case .openingMemory:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return BSLocalization.text("正在现场，拍一张或写一句，留下此刻。")
            }
            return BSLocalization.format("%@ 正在现场，拍一张或写一句，留下此刻。", trimmed)
        }
    }

    private func notificationTitle(
        for milestone: ShowNotificationMilestone,
        context: NotificationCopyContext
    ) -> String {
        switch milestone {
        case .fourteenDaysBefore:
            return BSLocalization.text("开场之前，先进入状态")
        case .sevenDaysBefore:
            return BSLocalization.text("还有一周")
        case .threeDaysBefore:
            return BSLocalization.text("该想想带什么了")
        case .oneDayBefore:
            return BSLocalization.text("明天见")
        case .showDayMorning:
            return BSLocalization.text("今天开场")
        case .showDay:
            return BSLocalization.text("快开场了")
        case .afterShow:
            return BSLocalization.text("昨天怎么样")
        case .openingMemory:
            return BSLocalization.text("留下此刻")
        }
    }
}

// MARK: - Deep Link

enum NotificationUserInfoKey {
    static let showID = "showID"
    static let destination = "destination"
}

/// Payload carried in each notification's `userInfo`. Tapping a notification sets
/// the show as current and opens home.
struct NotificationDeepLink: Equatable, Sendable {
    enum Destination: String, Codable, Equatable, CaseIterable, Sendable {
        case home
        /// 散场后那条通知点进来直接开记忆碎片，否则回首页会落空。
        case memoryFragments
        /// 开场记忆通知点进来直接开统一记忆编辑器。
        case memoryCreate
    }

    let showID: UUID
    let destination: Destination

    init(showID: UUID, destination: Destination) {
        self.showID = showID
        self.destination = destination
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let parsed = Self.parse(userInfo: userInfo) else { return nil }
        self = parsed
    }

    static func parse(userInfo: [AnyHashable: Any]) -> NotificationDeepLink? {
        guard let rawDestination = userInfo[NotificationUserInfoKey.destination] as? String,
              let destination = Destination(rawValue: rawDestination),
              let rawShowID = userInfo[NotificationUserInfoKey.showID] as? String,
              let showID = UUID(uuidString: rawShowID) else {
            return nil
        }
        return NotificationDeepLink(showID: showID, destination: destination)
    }

    var userInfo: [AnyHashable: Any] {
        [
            NotificationUserInfoKey.showID: showID.uuidString,
            NotificationUserInfoKey.destination: destination.rawValue
        ]
    }
}

extension ShowNotificationMilestone {
    var deepLinkDestination: NotificationDeepLink.Destination {
        switch self {
        case .afterShow:
            return .memoryFragments
        case .openingMemory:
            return .memoryCreate
        case .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore,
             .oneDayBefore, .showDayMorning, .showDay:
            return .home
        }
    }
}

extension ScheduledShowNotification {
    var deepLink: NotificationDeepLink {
        NotificationDeepLink(showID: showID, destination: milestone.deepLinkDestination)
    }

    var userInfo: [AnyHashable: Any] {
        deepLink.userInfo
    }

    var requestIdentifier: String {
        if isBackfill {
            return "\(showID.uuidString).backfill.\(milestone.rawValue)"
        }
        return "\(showID.uuidString).\(milestone.rawValue)"
    }

    func makeNotificationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        // 同一现场的通知归到一组，等待期里不会散落成一串独立横幅。
        content.threadIdentifier = showID.uuidString
        if milestone.isTimeSensitive {
            // 唯一会响铃的：「快开场了」错过有真实后果。
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        } else {
            // 其余一律普通横幅：弹横幅、亮屏、进通知中心，但不带声音。
            content.sound = nil
            content.interruptionLevel = .active
            content.relevanceScore = isBackfill ? 0.7 : 0.5
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
    }
}

extension ShowNotificationScheduleRecord {
    var requestIdentifier: String {
        if isBackfill == true {
            return "\(showID.uuidString).backfill.\(milestoneRawValue)"
        }
        return "\(showID.uuidString).\(milestoneRawValue)"
    }
}

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
                requestsToSchedule.append(contentsOf: scheduler.backfillRequests(for: show, now: now))
                schedulingState.markBackfillMinted(showID: show.id)
            }
        }

        // 待发的补发不随重排丢弃：按记录原样重建（时刻和文案都是 mint 时定的，
        // 重算会得到另一组）。已删除现场的补发不再续命；已触发的（fireDate <= now）
        // 不重建，记录随下面的 recordsToCancel 清理。
        let liveShowIDs = Set(allShows.map(\.id))
        requestsToSchedule.append(contentsOf: existingRecords
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
            })

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

// MARK: - Deep Link Routing

@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    static let shared = NotificationDeepLinkRouter()

    @Published private(set) var pendingDeepLink: NotificationDeepLink?

    private init() {}

    func route(to deepLink: NotificationDeepLink) {
        pendingDeepLink = deepLink
    }

    @discardableResult
    func consume() -> NotificationDeepLink? {
        // Only clear when non-nil. Assigning `nil` while already `nil` still
        // fires `@Published` and can re-enter `.onReceive` → infinite layout loop
        // (seen as 100% CPU after leaving onboarding into the main TabView).
        guard let deepLink = pendingDeepLink else { return nil }
        pendingDeepLink = nil
        return deepLink
    }
}

/// Reads `userInfo` on notification tap (foreground and cold start) and routes the
/// deep link. Methods are `nonisolated` because the system calls them off the main
/// actor; only Sendable strings are carried into the main-actor task. Stateless, so
/// safe to share as a singleton.
final class BeforeShowNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = BeforeShowNotificationDelegate()

    private override init() {
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let showIDString = userInfo[NotificationUserInfoKey.showID] as? String
        let destinationString = userInfo[NotificationUserInfoKey.destination] as? String
        Task { @MainActor in
            var parsed: [AnyHashable: Any] = [:]
            if let showIDString { parsed[NotificationUserInfoKey.showID] = showIDString }
            if let destinationString { parsed[NotificationUserInfoKey.destination] = destinationString }
            if let deepLink = NotificationDeepLink(userInfo: parsed) {
                NotificationDeepLinkRouter.shared.route(to: deepLink)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 非「快开场了」的节点不带声音，前台只给横幅（见 makeNotificationRequest）。
        if notification.request.content.sound == nil {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
