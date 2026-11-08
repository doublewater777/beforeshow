import Foundation
import UserNotifications

/// Discs that a show's listening reminders point at, by local day: pending ones and those still in
/// Notification Center. Reading never reschedules anything.
enum ListeningReminderDayDiscs {
    static func read(showID: UUID, calendar: Calendar = .current) async -> [String: String] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map(\.request)
        return discIDsByDay(showID: showID, requests: delivered + pending, calendar: calendar)
    }

    static func discIDsByDay(showID: UUID, requests: [UNNotificationRequest], calendar: Calendar) -> [String: String] {
        let prefix = "\(showID.uuidString).\(ShowNotificationMilestone.listeningReminder.rawValue)."
        var result: [String: String] = [:]
        for request in requests where request.identifier.hasPrefix(prefix) {
            guard let seconds = TimeInterval(request.identifier.dropFirst(prefix.count)),
                  let discID = NotificationDeepLink(userInfo: request.content.userInfo)?.discID else { continue }
            let day = ListeningDailyFeaturedDiscPolicy.dayKey(for: Date(timeIntervalSince1970: seconds), calendar: calendar)
            result[day] = discID
        }
        return result
    }
}
