import Foundation
import SwiftData
import UserNotifications

// MARK: - Preparation Guide (read-only suggestion text fed into notification bodies)

struct ShowPreparationSection: Equatable, Identifiable {
    let id: UUID
    let title: String
    let suggestions: [ShowPreparationSuggestion]

    init(id: UUID = UUID(), title: String, suggestions: [ShowPreparationSuggestion]) {
        self.id = id
        self.title = title
        self.suggestions = suggestions
    }
}

struct ShowPreparationSuggestion: Equatable, Identifiable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct ShowPreparationGuide {
    func sections(for show: Show) -> [ShowPreparationSection] {
        var comfort = [
            ShowPreparationSuggestion(text: BSLocalization.text("按当天温度留一件好收纳的外套，排队和散场时会更从容。")),
            ShowPreparationSuggestion(text: BSLocalization.text("提前确认场馆对水杯、雨具和大件包的规则，少带难处理的东西。"))
        ]

        if isMultiDay(show) {
            comfort.append(
                ShowPreparationSuggestion(text: BSLocalization.text("跨天停留时间更长，可以准备防晒、轻便雨具和能坐下休息的小垫子。"))
            )
        }

        return [
            ShowPreparationSection(
                title: BSLocalization.text("天气和体感"),
                suggestions: comfort
            ),
            ShowPreparationSection(
                title: BSLocalization.text("现场礼仪"),
                suggestions: [
                    ShowPreparationSuggestion(text: BSLocalization.text("拍摄时留意身后视线，想记录也别挡住别人看向舞台。")),
                    ShowPreparationSuggestion(text: BSLocalization.text("散场人多时慢一点，先和同行的人约好汇合点。"))
                ]
            ),
            ShowPreparationSection(
                title: BSLocalization.text("注意事项"),
                suggestions: [
                    ShowPreparationSuggestion(text: BSLocalization.text("把入场凭证、身份证件和必要电量提前确认好，到了门口就不用慌。")),
                    ShowPreparationSuggestion(text: BSLocalization.text("如果散场后人多，提前和同行的人约好集合点。"))
                ]
            )
        ]
    }

    private func isMultiDay(_ show: Show, calendar: Calendar = .current) -> Bool {
        guard let endDate = show.endDate else { return false }
        return calendar.startOfDay(for: endDate) > calendar.startOfDay(for: show.date)
    }
}

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
    case twoDaysBefore
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
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        return milestoneDates(for: timeState, calendar: eventCalendar)
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
        let requests = newCurrentShow.map { futureRequests(for: $0, now: now) } ?? []

        return NotificationReschedulePlan(
            recordsToCancel: existingRecords,
            requestsToSchedule: requests
        )
    }

    private func milestoneDates(
        for timeState: CurrentShowTimeState,
        calendar: Calendar
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        [
            (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20, calendar: calendar)),
            (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20, calendar: calendar)),
            (.showDay, showDayReminderDate(for: timeState, calendar: calendar))
        ].compactMap { milestone, fireDate in
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

    private func showDayReminderDate(for timeState: CurrentShowTimeState, calendar: Calendar) -> Date? {
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
            return BSLocalization.format("%@ 还有两周，期待已经开始了", showName)
        case .sevenDaysBefore:
            return BSLocalization.format("%@ 还有 7 天，提前确认场馆对水杯、雨具和大件包的规则", showName)
        case .threeDaysBefore:
            return BSLocalization.format("%@ 还有 3 天，把入场凭证、身份证件和必要电量提前确认好", showName)
        case .twoDaysBefore:
            return BSLocalization.format("%@ 后天开场，按当天温度留一件好收纳的外套，排队散场更从容", showName)
        case .oneDayBefore:
            return BSLocalization.format("%@ 明天见，拍摄时留意身后视线，散场先和同行的人约好汇合点", showName)
        case .showDay:
            return BSLocalization.format("%@ 快开场了，凭证电量再确认一遍，出门别慌", showName)
        }
    }

    private func notificationTitle(for milestone: ShowNotificationMilestone) -> String {
        switch milestone {
        case .fourteenDaysBefore:
            return BSLocalization.text("开场之前，先进入状态")
        case .sevenDaysBefore:
            return BSLocalization.text("该想想带什么了")
        case .threeDaysBefore:
            return BSLocalization.text("票证装备确认")
        case .twoDaysBefore:
            return BSLocalization.text("出门前清单")
        case .oneDayBefore:
            return BSLocalization.text("明天见，最后看一眼")
        case .showDay:
            return BSLocalization.text("快开场了")
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
        case .fourteenDaysBefore: return .home
        case .sevenDaysBefore, .threeDaysBefore, .twoDaysBefore, .oneDayBefore, .showDay:
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
        content.sound = .default
        content.userInfo = userInfo
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
        let plan = scheduler.planFocusChange(from: existingRecords, to: show, now: now)
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
        completionHandler([.banner, .sound])
    }
}
