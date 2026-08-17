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
