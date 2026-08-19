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
    /// 只有「快开场了」错过会有真实后果，其余都安静待在通知中心。
    var isTimeSensitive: Bool {
        self == .showDay
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
                return BSLocalization.format("%1$@ 还有一周，可以先熟悉一下 %2$@ 怎么去", name, place)
            }
            return BSLocalization.format("%@ 还有一周，可以先想想那天的样子了", name)

        case .threeDaysBefore:
            switch context.flavor {
            case .festival:
                return BSLocalization.format("%@ 还有三天，防晒、雨具和能坐下歇脚的东西可以先备好", name)
            case .livehouse:
                return BSLocalization.format("%@ 还有三天，站场时间不短，选一双好走的鞋", name)
            case .concert:
                return BSLocalization.format("%@ 还有三天，入场凭证和身份证件先确认一遍", name)
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
            return BSLocalization.format("%@ 快开场了，凭证电量再确认一遍", name)

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
            return BSLocalization.text("明天见，最后看一眼")
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
        "\(showID.uuidString).\(milestone.rawValue)"
    }

    func makeNotificationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        // 同一现场的通知归到一组，等待期里不会散落成一串独立横幅。
        content.threadIdentifier = showID.uuidString
        if milestone.isTimeSensitive {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        } else {
            // 进入状态的过程不该被打断：安静送达，留在通知中心里等用户自己看。
            content.sound = nil
            content.interruptionLevel = .passive
            content.relevanceScore = 0.5
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
        "\(showID.uuidString).\(milestone.rawValue)"
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
    /// Missed milestones are never backfilled; only future fire dates are scheduled.
    @discardableResult
    func applyFocusChange(to show: Show?, in context: ModelContext, now: Date = Date()) async -> Bool {
        let existingRecords = (try? context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())) ?? []
        // 已确认散场的现场即使让出焦点，它的 afterShow 也要继续排。
        let endedShows = ((try? context.fetch(FetchDescriptor<Show>())) ?? [])
            .filter { $0.endedAt != nil }
        let plan = scheduler.planFocusChange(
            from: existingRecords,
            to: show,
            preservingAfterShowOf: endedShows,
            now: now
        )
        var didScheduleEveryRequest = true

        let identifiersToCancel = plan.recordsToCancel.map(\.requestIdentifier)
        if !identifiersToCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        }
        for record in plan.recordsToCancel {
            context.delete(record)
        }

        for request in plan.requestsToSchedule {
            let record = ShowNotificationScheduleRecord(
                showID: request.showID,
                milestone: request.milestone,
                fireDate: request.fireDate
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
                withIdentifiers: plan.requestsToSchedule.map(\.requestIdentifier)
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
        let recordedIdentifiers = Set(existingRecords.map(\.requestIdentifier))
        let desiredIdentifiers = Set(desired.map(\.requestIdentifier))

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
        // 安静节点在前台也不响铃，只有「快开场了」带声音（见 makeNotificationRequest）。
        if notification.request.content.sound == nil {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
