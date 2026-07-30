import Foundation

// MARK: - Widget Timeline Planner
// 纯逻辑:滚动 12h 窗口、窗口内边界、边界优先去重。
// app tests 与 widget provider 共用,避免 .atEnd + 远期边界冻结数天。

enum WidgetTimelinePlanner {
    static let refreshWindow: TimeInterval = 12 * 3_600

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
        if let start = startBoundary, start > now, start <= windowEnd {
            dates.append(start)
            boundaryRefs.insert(start.timeIntervalSinceReferenceDate)
        }
        if let end = endBoundary, end > now, end <= windowEnd {
            dates.append(end)
            boundaryRefs.insert(end.timeIntervalSinceReferenceDate)
        }
        dates.append(windowEnd)

        let sorted = dates.sorted()
        var kept: [Date] = []
        for date in sorted {
            let isBoundary = boundaryRefs.contains(date.timeIntervalSinceReferenceDate)
            if let last = kept.last {
                let delta = abs(last.timeIntervalSince(date))
                if delta < 0.5 {
                    continue
                }
                if delta <= 60 {
                    let lastIsBoundary = boundaryRefs.contains(last.timeIntervalSinceReferenceDate)
                    if isBoundary && !lastIsBoundary {
                        kept.removeLast()
                        kept.append(date)
                    }
                    continue
                }
            }
            kept.append(date)
        }
        return (kept, windowEnd)
    }

    /// Live Activity 最早启动时刻:保证 activityEnd - start ≤ 8h。
    static func liveActivityEarliestStart(
        activityEnd: Date,
        maxActiveDuration: TimeInterval = 8 * 3_600
    ) -> Date {
        activityEnd.addingTimeInterval(-maxActiveDuration)
    }
}
