import Foundation

enum ShowChangeStatus: String, CaseIterable, Codable, Equatable {
    case scheduled
    case postponed
    case canceled
}

/// 现场的时间字段，纯值类型——SwiftData `Show` 与 widget 快照共用同一组输入，
/// 让 `CurrentShowTimeState` 可以脱离 @Model 在 extension 进程里重算倒计时。
struct ShowTimingFields: Equatable, Codable {
    var date: Date
    var startTime: Date
    var endDate: Date?
    var endTime: Date?
    /// Fixed UTC offset reported by an external event page, when available.
    /// The Date values remain absolute instants; this offset preserves the
    /// venue-local calendar and clock when timing is displayed or recomputed.
    var timeZoneSecondsFromGMT: Int? = nil
    /// The end instant may carry a different fixed offset across a DST boundary.
    var endTimeZoneSecondsFromGMT: Int? = nil
    var endedAt: Date? = nil
    var postponedDate: Date?
    var changeStatus: ShowChangeStatus

    var effectiveDate: Date {
        postponedDate ?? date
    }

    func eventCalendar(fallback: Calendar) -> Calendar {
        guard let timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: timeZoneSecondsFromGMT) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }

    func endEventCalendar(fallback: Calendar) -> Calendar {
        guard let offset = endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: offset) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }
}

enum ShowDateSelectionPolicy {
    static func normalizedDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
}
