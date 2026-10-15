import Foundation

/// App 与小组件共用的日期时间格式。
///
/// 时刻一律 24 小时制（音乐节时刻表惯例），不随系统 12/24 小时设置变化；
/// 日期部分仍按用户语言本地化。
enum BSDateFormat {
    /// "19:30"
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        ))
    }

    /// "2026.10.15"，分享卡片与足迹抬头使用，不随语言变化。
    static func dottedDate(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits)",
            timeZone: calendar.timeZone,
            calendar: calendar
        ))
    }

    /// 本地化的日期加 24 小时制时刻，例如 "Oct 15, 2026 at 19:30" / "2026年10月15日 19:30"。
    static func dateTime(_ date: Date, timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        Date.FormatStyle(date: .abbreviated, time: .shortened, locale: twentyFourHour(locale), timeZone: timeZone)
            .format(date)
    }

    static func twentyFourHour(_ locale: Locale) -> Locale {
        var components = Locale.Components(locale: locale)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }
}
