import Foundation

/// 现场观看时长文案。
/// 单场：< 24 小时用「X 小时 Y 分」,≥ 24 小时(跨日现场)用「N 天 X 小时」。
/// 累计：< 100 小时用「N 小时」,≥ 100 小时用「N 天 X 小时」。
enum ShowDurationFormatter {
    /// 累计时长进入「天」形态的阈值(小时)。
    static let aggregateDayThresholdHours = 100

    /// 单场时长文案。end <= start 时返回 nil,让上层跳过展示。
    static func single(from start: Date, to end: Date) -> String? {
        guard let minutes = minutes(from: start, to: end) else { return nil }
        return single(totalMinutes: minutes)
    }

    /// 单场时长文案(分钟)。≥ 24 小时的跨日现场用「N 天 X 小时」。
    static func single(totalMinutes: Int) -> String {
        if totalMinutes >= 24 * 60 {
            return daysText(days: totalMinutes / (24 * 60), restHours: (totalMinutes % (24 * 60)) / 60)
        }
        return hoursMinutesText(totalMinutes: totalMinutes)
    }

    /// 多场累计时长文案,总量按小时取整后展示。
    static func aggregate(totalMinutes: Int) -> String {
        let totalHours = max(0, totalMinutes) / 60
        guard totalHours >= aggregateDayThresholdHours else {
            return BSLocalization.format("%lld 小时", totalHours)
        }
        return daysText(days: totalHours / 24, restHours: totalHours % 24)
    }

    /// 单场观看时长(分钟):已确认散场用真实时刻,否则用录入的结束时间,
    /// 再否则回落到默认估算(endBoundary)。无法计算时返回 nil。
    static func minutes(for show: Show, timeState: CurrentShowTimeState) -> Int? {
        let start = timeState.effectiveStartTime
            ?? CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar())
        guard let end = show.endedAt ?? timeState.effectiveEndTime ?? timeState.endBoundary else {
            return nil
        }
        return minutes(from: start, to: end)
    }

    static func minutes(from start: Date, to end: Date) -> Int? {
        guard end > start else { return nil }
        return Int(end.timeIntervalSince(start)) / 60
    }

    /// 「X 小时 Y 分」/「X 小时」/「X 分钟」。
    private static func hoursMinutesText(totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let rest = totalMinutes % 60
        if hours > 0 && rest > 0 {
            return BSLocalization.format("%lld 小时 %lld 分", hours, rest)
        } else if hours > 0 {
            return BSLocalization.format("%lld 小时", hours)
        } else {
            return BSLocalization.format("%lld 分钟", max(1, rest))
        }
    }

    /// 「N 天 X 小时」,余 0 小时时为「N 天」。
    private static func daysText(days: Int, restHours: Int) -> String {
        if restHours > 0 {
            return BSLocalization.format("%lld 天 %lld 小时", days, restHours)
        }
        return BSLocalization.format("%lld 天", days)
    }
}

/// Show 的日期/时间展示格式化。
///
/// 展示文案属于 presentation concern，不放在 SwiftData `Show` 模型文件里；
/// 这样模型文件只保留持久化字段、校验和领域 mutation。
struct ShowDisplayFormatter {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func dateText(for show: Show) -> String {
        let calendar = show.timingCalendar(fallback: calendar)
        let endCalendar = show.endTimingCalendar(fallback: calendar)
        let startDay = show.effectiveDate
        let startClock = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar)
        let endClock = CurrentShowTimeState.effectiveEndTime(
            for: show,
            calendar: calendar,
            effectiveDate: show.effectiveDate,
            effectiveStartTime: startClock
        )

        // 多日每日循环：共用 startTime / endTime 钟点，展示「日期区间 · 每日 HH:mm[-HH:mm]」。
        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay {
            let range = dayRangeText(from: startDay, to: endDay, calendar: calendar)
            if let endTime = show.endTime {
                return BSLocalization.format("%@ · 每日 %@-%@", range, timeText(startClock, calendar: calendar), timeText(endTime, calendar: endCalendar))
            }
            return BSLocalization.format("%@ · 每日 %@", range, timeText(startClock, calendar: calendar))
        }

        var text = dateText(startDay, calendar: calendar)
        text += " \(timeText(startClock, calendar: calendar))"

        if let endClock {
            let formattedEnd = shortDateTimeText(
                endClock,
                includeDateWhenSameDayAs: startDay,
                calendar: endCalendar,
                sameDayCalendar: calendar
            )
            text += " - \(formattedEnd)"
        } else if let endDay,
                  calendar.startOfDay(for: endDay) > calendar.startOfDay(for: startDay) {
            text += " - \(shortDateText(endDay, calendar: endCalendar))"
        }

        return text
    }

    private func dayRangeText(from start: Date, to end: Date, calendar: Calendar) -> String {
        let startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: end)
        let year = startComponents.year ?? calendar.component(.year, from: start)
        let startMonth = startComponents.month ?? 1
        let startDay = startComponents.day ?? 1
        let endMonth = endComponents.month ?? 1
        let endDay = endComponents.day ?? 1

        if startMonth == endMonth {
            return BSLocalization.format("%lld年%lld月%lld日-%lld日", year, startMonth, startDay, endDay)
        }
        return BSLocalization.format("%lld年%lld月%lld日-%lld月%lld日", year, startMonth, startDay, endMonth, endDay)
    }

    private func dateText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return BSLocalization.format("%lld年%lld月%lld日", components.year ?? 0, components.month ?? 1, components.day ?? 1)
    }

    private func shortDateText(_ date: Date, calendar: Calendar? = nil) -> String {
        let components = (calendar ?? self.calendar).dateComponents([.month, .day], from: date)
        return BSLocalization.format("%lld月%lld日", components.month ?? 1, components.day ?? 1)
    }

    private func shortDateTimeText(
        _ date: Date,
        includeDateWhenSameDayAs startDay: Date,
        calendar: Calendar,
        sameDayCalendar: Calendar
    ) -> String {
        if sameDayCalendar.isDate(date, inSameDayAs: startDay) {
            return timeText(date, calendar: calendar)
        }
        return "\(shortDateText(date, calendar: calendar)) \(timeText(date, calendar: calendar))"
    }

    private func timeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
