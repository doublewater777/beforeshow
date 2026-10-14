import Foundation

/// One countdown unit policy for the app, upcoming-show list, and widgets.
/// Show-local calendar days and elapsed-time thresholds serve different purposes.
enum ShowCountdownRule {
    enum Value: Equatable {
        case days(Int)
        case hours(Int)
        case minutes(Int)

        var number: Int {
            switch self {
            case .days(let value), .hours(let value), .minutes(let value):
                return value
            }
        }
    }

    /// Exactly 24 hours already uses the hour/minute clock mode.
    static let dayThreshold: TimeInterval = 86_400

    static func calendarDays(from now: Date, to eventDate: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: eventDate)
        ).day ?? 0
    }

    static func isDayCount(remainingSeconds: Int) -> Bool {
        remainingSeconds > Int(dayThreshold)
    }

    static func dayCount(remainingSeconds: Int, dayDistance: Int) -> Int? {
        guard isDayCount(remainingSeconds: remainingSeconds), dayDistance > 0 else { return nil }
        return dayDistance
    }

    static func near(remainingSeconds: Int) -> Value {
        let seconds = max(0, remainingSeconds)
        if seconds >= 3_600 { return .hours(seconds / 3_600) }
        return .minutes(max(1, seconds / 60))
    }

    static func upcoming(remainingSeconds: Int, dayDistance: Int) -> Value {
        if let days = dayCount(remainingSeconds: remainingSeconds, dayDistance: dayDistance) {
            return .days(days)
        }
        return near(remainingSeconds: remainingSeconds)
    }

    static func upcoming(from now: Date, to start: Date, calendar: Calendar) -> Value {
        upcoming(
            remainingSeconds: max(0, Int(start.timeIntervalSince(now))),
            dayDistance: calendarDays(from: now, to: start, calendar: calendar)
        )
    }
}

/// Localization stays presentation-specific; numeric unit selection is shared.
enum CountdownCopy {
    static func value(remainingSeconds: Int) -> Int {
        ShowCountdownRule.near(remainingSeconds: remainingSeconds).number
    }

    static func until(remainingSeconds: Int, dayDistance: Int = 0) -> String {
        switch ShowCountdownRule.upcoming(
            remainingSeconds: remainingSeconds,
            dayDistance: dayDistance
        ) {
        case .days(let days):
            return BSLocalization.format("%lld 天后", Int64(days))
        case .hours(let hours):
            return BSLocalization.format("%lld 小时后", Int64(hours))
        case .minutes(let minutes):
            return BSLocalization.format("%lld 分钟后", Int64(minutes))
        }
    }
}
