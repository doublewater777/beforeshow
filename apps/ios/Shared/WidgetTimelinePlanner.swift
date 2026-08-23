import Foundation

// MARK: - Countdown Time Presentation

/// App 首页与普通 widget 共用的时间精度。开场前越近越精确；开场后重新收束，
/// 避免把「正在现场」做成秒表。
enum CountdownTimeDisplay: Equatable {
    case days(Int)
    case hours(Int)
    case minutesSeconds(minutes: Int, seconds: Int)
    case elapsedMinutes(Int)
    case elapsedHoursMinutes(hours: Int, minutes: Int)
}

enum CountdownTimePresentationPolicy {
    static let hourThreshold: TimeInterval = 3_600

    static func beforeStart(remainingSeconds: Int) -> CountdownTimeDisplay {
        let total = max(0, remainingSeconds)
        if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: total) {
            return .days(total / Int(WidgetTimelinePlanner.dayCountdownThreshold))
        }
        // 「最后 1 小时」从 remaining == 3600 就进入分秒；3601 仍是小时。
        if total > Int(hourThreshold) {
            return .hours(max(1, total / Int(hourThreshold)))
        }
        return .minutesSeconds(
            minutes: total / 60,
            seconds: total % 60
        )
    }

    static func afterStart(elapsedSeconds: Int) -> CountdownTimeDisplay {
        let total = max(0, elapsedSeconds)
        if total < Int(hourThreshold) {
            return .elapsedMinutes(total / 60)
        }
        return .elapsedHoursMinutes(
            hours: total / Int(hourThreshold),
            minutes: (total % Int(hourThreshold)) / 60
        )
    }
}

// MARK: - Widget Timeline Planner
// 纯逻辑:滚动 12h 窗口、窗口内边界、边界优先去重。
// app tests 与 widget provider 共用,避免 .atEnd + 远期边界冻结数天。
// Live Activity 的窗口计算在 LiveActivityPlanner,不在这里。

enum WidgetTimelinePlanner {
    static let refreshWindow: TimeInterval = 12 * 3_600
    /// 首页 / widget 共用:剩余 **大于** 此值显示「N 天」,≤ 则切到小时或最后一小时的分秒。
    /// 用 `>` 而非 `>=`:timeline 在 start−24h 插入的 entry 上 remaining 恰为 86400,
    /// 必须已经切到小时,否则仍显示「1 天」直到下一小时点。
    static let dayCountdownThreshold: TimeInterval = 86_400

    /// 是否用天数 hero。threshold entry(remaining == 86400) 必须为 false → 小时。
    static func isDayCountHero(remainingSeconds: Int) -> Bool {
        remainingSeconds > Int(dayCountdownThreshold)
    }

    /// 生成 timeline 日期点(已排序、已去重)。最后一个始终是窗口终点。
    static func entryDates(
        now: Date,
        startBoundary: Date?,
        endBoundary: Date?,
        calendar: Calendar = .current
    ) -> (dates: [Date], windowEnd: Date) {
        let windowEnd = now.addingTimeInterval(refreshWindow)
        var dates: [Date] = [now]
        for hour in 1...11 {
            if let date = calendar.date(byAdding: .hour, value: hour, to: now), date <= windowEnd {
                dates.append(date)
            }
        }

        var boundaryRefs: Set<TimeInterval> = []
        func appendBoundary(_ date: Date) {
            guard date > now, date <= windowEnd else { return }
            dates.append(date)
            boundaryRefs.insert(date.timeIntervalSinceReferenceDate)
        }

        if let start = startBoundary {
            appendBoundary(start)

            // >24h → 天；remaining == 24h 起进入整小时。
            appendBoundary(start.addingTimeInterval(-dayCountdownThreshold))

            // 整小时 hero 使用 floor 语义，因此必须在 start−Nh 的真实边界刷新，
            // 不能只按 provider 的 now+1h 滚动，否则 5h23m 会把「5 小时」多挂约 37 分钟。
            // 1h 边界同时负责切到最后一小时的「分 + 秒」。24h 已由上面的 day 边界覆盖。
            for remainingHours in 1...23 {
                appendBoundary(
                    start.addingTimeInterval(
                        -TimeInterval(remainingHours) * CountdownTimePresentationPolicy.hourThreshold
                    )
                )
            }
        }
        if let end = endBoundary {
            appendBoundary(end)
        }
        dates.append(windowEnd)

        let sorted = dates.sorted()
        let nowRef = now.timeIntervalSinceReferenceDate
        var kept: [Date] = []
        for date in sorted {
            let isBoundary = boundaryRefs.contains(date.timeIntervalSinceReferenceDate)
            if let last = kept.last {
                let delta = abs(last.timeIntervalSince(date))
                if delta < 0.5 {
                    continue
                }
                if delta <= 60 {
                    // 边界优先于小时 entry(替换它);但当前时刻 entry 永远保留——
                    // WidgetKit 约定首条 = 当前状态,边界紧随其后共存即可
                    let lastIsBoundary = boundaryRefs.contains(last.timeIntervalSinceReferenceDate)
                    let lastIsNow = last.timeIntervalSinceReferenceDate == nowRef
                    if isBoundary && !lastIsBoundary && !lastIsNow {
                        kept.removeLast()
                        kept.append(date)
                    } else if isBoundary && lastIsNow {
                        kept.append(date)
                    }
                    continue
                }
            }
            kept.append(date)
        }
        return (kept, windowEnd)
    }
}
