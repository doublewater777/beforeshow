import Foundation
import UserNotifications

enum ListeningNotificationCategory {
    static let identifier = "listeningReminder"
    static let playActionIdentifier = "playListeningDisc"

    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: identifier, actions: [
            UNNotificationAction(identifier: playActionIdentifier, title: BSLocalization.text("播放"), options: [.foreground])
        ], intentIdentifiers: [])
    }
}

extension ScheduledShowNotification {
    var categoryIdentifier: String {
        milestone == .listeningReminder || (discID != nil && (milestone == .oneDayBefore || milestone == .showDay))
            ? ListeningNotificationCategory.identifier : ""
    }

    var deepLink: NotificationDeepLink {
        NotificationDeepLink(showID: showID, destination: destination, feature: feature, discID: discID, artistID: artistID, artistName: artistName)
    }

    var userInfo: [AnyHashable: Any] {
        deepLink.userInfo
    }

    var requestIdentifier: String {
        if milestone == .listeningReminder {
            return "\(showID.uuidString).\(milestone.rawValue).\(Int(fireDate.timeIntervalSince1970))"
        }
        if let performanceID {
            return "\(showID.uuidString).\(milestone.rawValue).\(performanceID.uuidString)"
        }
        return "\(showID.uuidString).\(milestone.rawValue)"
    }

    func makeNotificationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.categoryIdentifier = categoryIdentifier
        // 同一现场的通知归到一组，等待期里不会散落成一串独立横幅。
        content.threadIdentifier = showID.uuidString
        if milestone.isTimeSensitive {
            // 唯一会响铃的：「开场前 3 小时」错过有真实后果。
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        } else if milestone.isPassive {
            // 开场与刚散场：不亮屏、不响，留在通知中心。
            content.sound = nil
            content.interruptionLevel = .passive
            content.relevanceScore = 0.3
        } else {
            // 其余一律普通横幅：弹横幅、亮屏、进通知中心，但不带声音。
            content.sound = nil
            content.interruptionLevel = .active
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
        if milestoneRawValue == "listeningReminder" {
            return "\(showID.uuidString).\(milestoneRawValue).\(Int(fireDate.timeIntervalSince1970))"
        }
        if isBackfill == true {
            return "\(showID.uuidString).backfill.\(milestoneRawValue)"
        }
        if let performanceID {
            return "\(showID.uuidString).\(milestoneRawValue).\(performanceID.uuidString)"
        }
        return "\(showID.uuidString).\(milestoneRawValue)"
    }
}
