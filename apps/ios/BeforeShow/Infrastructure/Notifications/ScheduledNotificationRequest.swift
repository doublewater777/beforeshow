import Foundation
import UserNotifications

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
