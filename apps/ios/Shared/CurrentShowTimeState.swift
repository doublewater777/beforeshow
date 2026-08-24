import Foundation

enum CountdownCopy {
    static func value(remainingSeconds: Int) -> Int {
        let remaining = max(0, remainingSeconds)
        if remaining >= 3_600 {
            return remaining / 3_600
        }
        return max(1, remaining / 60)
    }

    static func until(remainingSeconds: Int) -> String {
        let remaining = max(0, remainingSeconds)
        if remaining >= 3_600 {
            return BSLocalization.format("%lld 小时后", Int64(value(remainingSeconds: remaining)))
        }
        return BSLocalization.format("%lld 分钟后", Int64(value(remainingSeconds: remaining)))
    }
}

enum CurrentShowTimeKind: Equatable {
    case before
    case today
    /// 多日现场：当日已谢幕，但后续日还未结束（第二天会重新 pre → live）。
    case dayEnded
    case postShow
    case ended
    case canceled
    case postponed
}

/// Phase / countdown state for a 现场. Presentation layout lives in views, not here.
/// 输入是 `ShowTimingFields` 纯值，app（SwiftData Show）与 widget extension（快照）共用。
struct CurrentShowTimeState: Equatable {
    static let defaultRetentionDays = 3

    let kind: CurrentShowTimeKind
    let dayDistance: Int
    let retentionDays: Int
    let effectiveDate: Date
    let effectiveEndDate: Date?
    let effectiveStartTime: Date?
    let effectiveEndTime: Date?
    /// Resolved show-end instant for the *current* phase boundary.
    /// Multi-day daily cycle: today's daily end (or last day's end after the run).
    /// Single / overnight: whole-event end. Drives live→ended and 本场时长.
    let endBoundary: Date?
    let hasKnownEffectiveDate: Bool
    let isDatedPostponement: Bool
    let countdownText: String
    let countdownNumber: String
    let countdownUnit: String
    let helperText: String

    init(
        timing: ShowTimingFields,
        calendar: Calendar = .current,
        now: Date = Date(),
        retentionDays: Int = Self.defaultRetentionDays
    ) {
        let eventCalendar = timing.eventCalendar(fallback: calendar)
        self.retentionDays = retentionDays
        self.hasKnownEffectiveDate = !(timing.changeStatus == .postponed && timing.postponedDate == nil)
        self.isDatedPostponement = timing.changeStatus == .postponed && timing.postponedDate != nil
        self.effectiveDate = timing.effectiveDate

        let resolvedEndDate = hasKnownEffectiveDate
            ? Self.effectiveEndDate(timing: timing, calendar: eventCalendar)
            : nil
        self.effectiveEndDate = resolvedEndDate

        let today = eventCalendar.startOfDay(for: now)
        let showDay = eventCalendar.startOfDay(for: effectiveDate)
        let daysToFirst = eventCalendar.dateComponents([.day], from: today, to: showDay).day ?? 0
        self.dayDistance = daysToFirst

        let multiDayDaily = hasKnownEffectiveDate
            && Self.isMultiDayDailyCycle(timing: timing, calendar: eventCalendar)

        let resolvedStart: Date?
        let resolvedEnd: Date?
        let resolvedBoundary: Date?
        let resolvedKind: CurrentShowTimeKind

        if timing.changeStatus == .canceled {
            resolvedStart = hasKnownEffectiveDate
                ? Self.effectiveStartTime(timing: timing, calendar: eventCalendar)
                : nil
            resolvedEnd = nil
            resolvedBoundary = nil
            resolvedKind = .canceled
        } else if !hasKnownEffectiveDate {
            resolvedStart = nil
            resolvedEnd = nil
            resolvedBoundary = nil
            resolvedKind = .postponed
        } else if let endedAt = timing.endedAt {
            if multiDayDaily {
                let endedDay = eventCalendar.startOfDay(for: endedAt)
                let endedDayStart = Self.dailyStartTime(on: endedDay, timing: timing, calendar: eventCalendar)
                let candidateSessionDay: Date
                if endedAt < endedDayStart,
                   let previousDay = eventCalendar.date(byAdding: .day, value: -1, to: endedDay) {
                    candidateSessionDay = previousDay
                } else {
                    candidateSessionDay = endedDay
                }
                let finalDay = eventCalendar.startOfDay(for: resolvedEndDate ?? effectiveDate)
                let sessionDay = min(candidateSessionDay, finalDay)
                resolvedStart = Self.dailyStartTime(on: sessionDay, timing: timing, calendar: eventCalendar)
            } else {
                resolvedStart = Self.effectiveStartTime(timing: timing, calendar: eventCalendar)
            }
            resolvedEnd = endedAt
            resolvedBoundary = endedAt

            if now < endedAt {
                resolvedKind = .today
            } else if let retentionEnd = eventCalendar.date(byAdding: .day, value: retentionDays, to: endedAt),
                      now < retentionEnd {
                resolvedKind = .postShow
            } else {
                resolvedKind = .ended
            }
        } else if multiDayDaily {
            let lastDay = eventCalendar.startOfDay(for: resolvedEndDate ?? effectiveDate)
            let finalEnd = Self.dailyEndTime(on: lastDay, timing: timing, calendar: eventCalendar)
            // 跨午夜时，凌晨仍属于前一天的场次（例如 22:00–01:00）。
            let sessionDay: Date = {
                if today < showDay { return showDay }
                if today > lastDay { return lastDay }
                guard today > showDay,
                      let previousDay = eventCalendar.date(byAdding: .day, value: -1, to: today),
                      previousDay >= showDay else { return today }
                let previousStart = Self.dailyStartTime(on: previousDay, timing: timing, calendar: eventCalendar)
                let previousEnd = Self.dailyEndTime(on: previousDay, timing: timing, calendar: eventCalendar)
                return now >= previousStart && now < previousEnd ? previousDay : today
            }()
            let dayStart = Self.dailyStartTime(on: sessionDay, timing: timing, calendar: eventCalendar)
            let dayEnd = Self.dailyEndTime(on: sessionDay, timing: timing, calendar: eventCalendar)
            resolvedStart = dayStart
            resolvedEnd = dayEnd
            resolvedBoundary = today < showDay ? finalEnd : dayEnd

            if today < showDay {
                resolvedKind = .before
            } else if now < dayStart {
                resolvedKind = .today
            } else if now < dayEnd {
                resolvedKind = .today
            } else if sessionDay < lastDay {
                resolvedKind = .dayEnded
            } else if let retentionEnd = eventCalendar.date(byAdding: .day, value: retentionDays, to: dayEnd),
                      now < retentionEnd {
                resolvedKind = .postShow
            } else {
                resolvedKind = .ended
            }
        } else {
            let firstStart = Self.effectiveStartTime(timing: timing, calendar: eventCalendar)
            let wholeEnd = Self.effectiveEndTime(
                timing: timing,
                calendar: eventCalendar,
                effectiveDate: timing.effectiveDate,
                effectiveStartTime: firstStart
            )
            let boundary = Self.effectiveEndBoundary(
                timing: timing,
                calendar: eventCalendar,
                effectiveDate: effectiveDate,
                effectiveEndDate: resolvedEndDate,
                effectiveEndTime: wholeEnd
            )
            resolvedStart = firstStart
            resolvedEnd = wholeEnd
            resolvedBoundary = boundary

            if today < showDay {
                resolvedKind = .before
            } else if let boundary, now < boundary {
                resolvedKind = .today
            } else if let boundary,
                      let retentionEnd = eventCalendar.date(byAdding: .day, value: retentionDays, to: boundary),
                      now < retentionEnd {
                resolvedKind = .postShow
            } else {
                resolvedKind = .ended
            }
        }

        self.effectiveStartTime = resolvedStart
        self.effectiveEndTime = resolvedEnd
        self.endBoundary = resolvedBoundary
        self.kind = resolvedKind

        let countdown = Self.countdownCopy(
            kind: resolvedKind,
            dayDistance: daysToFirst,
            startTime: resolvedStart,
            endBoundary: resolvedBoundary,
            now: now,
            retentionDays: retentionDays,
            calendar: eventCalendar
        )
        self.countdownText = countdown.text
        self.countdownNumber = countdown.number
        self.countdownUnit = countdown.unit
        self.helperText = countdown.helper
    }

    var isAutomaticallySelectable: Bool {
        switch kind {
        case .before, .today, .dayEnded, .postShow:
            return true
        case .ended, .canceled, .postponed:
            return false
        }
    }

    /// 估算散场边界(start+默认时长 / 每日末场)已过,但用户尚未确认 endedAt。
    /// 首页与 widget 共用:此时只说「待确认 / 已到预计结束时间」,不提前宣布「已落幕 / ENDED」。
    static func isUnconfirmedEstimatedEnd(kind: CurrentShowTimeKind, hasConfirmedEnd: Bool) -> Bool {
        !hasConfirmedEnd && (kind == .postShow || kind == .ended)
    }

    var canScheduleNotifications: Bool {
        hasKnownEffectiveDate && kind != .canceled
    }

    var title: String {
        switch kind {
        case .before: return BSLocalization.text("开场前")
        case .today: return BSLocalization.text("今天开场")
        case .dayEnded: return BSLocalization.text("今日已落幕")
        case .postShow: return BSLocalization.text("散场后")
        case .ended: return BSLocalization.text("已结束")
        case .canceled: return BSLocalization.text("已取消")
        case .postponed: return BSLocalization.text("时间待定")
        }
    }

    var statusText: String {
        if kind == .canceled {
            return BSLocalization.text("已取消")
        }
        if !hasKnownEffectiveDate {
            return BSLocalization.text("已延期，时间待定")
        }
        if isDatedPostponement {
            return BSLocalization.text("已延期")
        }

        switch kind {
        case .today:
            return BSLocalization.text("当天")
        case .dayEnded:
            return BSLocalization.text("今日已落幕")
        case .postShow, .ended:
            return BSLocalization.text("已结束")
        case .before:
            return BSLocalization.text("开场前")
        case .canceled:
            return BSLocalization.text("已取消")
        case .postponed:
            return BSLocalization.text("已延期，时间待定")
        }
    }

    // MARK: - Shared timing helpers

    /// 多日「每日循环」：有跨日 endDate，且不是一夜连轴（次日凌晨落幕）的单场。
    /// 每日共用同一个 startTime / endTime 钟点。
    static func isMultiDayDailyCycle(timing: ShowTimingFields, calendar: Calendar) -> Bool {
        guard let endDate = effectiveEndDate(timing: timing, calendar: calendar) else {
            return false
        }
        let startDay = calendar.startOfDay(for: timing.effectiveDate)
        let endDay = calendar.startOfDay(for: endDate)
        guard endDay > startDay else { return false }

        let span = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        // 跨午夜单场：仅 +1 日，且结束钟点 ≤ 开场钟点（如 23:00–01:00）。
        if span == 1, let endTime = timing.endTime {
            let endCalendar = timing.endEventCalendar(fallback: calendar)
            if minutesOfDay(endTime, calendar: endCalendar) <= minutesOfDay(timing.startTime, calendar: calendar) {
                return false
            }
        }
        return true
    }

    static func effectiveStartTime(timing: ShowTimingFields, calendar: Calendar) -> Date {
        guard let merged = merge(time: timing.startTime, into: timing.effectiveDate, calendar: calendar) else {
            return timing.startTime
        }
        return merged
    }

    static func effectiveEndDate(timing: ShowTimingFields, calendar: Calendar) -> Date? {
        guard let endDate = timing.endDate else {
            return nil
        }
        let endCalendar = timing.endEventCalendar(fallback: calendar)
        let endDayComponents = endCalendar.dateComponents([.year, .month, .day], from: endDate)
        let comparableEndDay = calendar.date(from: endDayComponents) ?? calendar.startOfDay(for: endDate)
        guard let postponedDate = timing.postponedDate else {
            return comparableEndDay
        }

        let originalStartDay = calendar.startOfDay(for: timing.date)
        let dayOffset = calendar.dateComponents([.day], from: originalStartDay, to: comparableEndDay).day ?? 0
        let postponedStartDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: postponedDate))
            ?? calendar.startOfDay(for: postponedDate)
        let postponedComponents = calendar.dateComponents([.year, .month, .day], from: postponedStartDay)
        return calendar.date(from: postponedComponents) ?? comparableEndDay
    }

    static func effectiveEndTime(
        timing: ShowTimingFields,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveStartTime: Date?
    ) -> Date? {
        guard let endTime = timing.endTime else {
            return nil
        }

        // 多日每日循环：endTime 是每日共用钟点，落到传入的 effectiveDate（通常为首日）上。
        if isMultiDayDailyCycle(timing: timing, calendar: calendar) {
            return dailyEndTime(on: calendar.startOfDay(for: effectiveDate), timing: timing, calendar: calendar)
        }

        let endCalendar = timing.endEventCalendar(fallback: calendar)
        let endDay = Self.effectiveEndDate(timing: timing, calendar: calendar) ?? effectiveDate
        let endDayComponents = calendar.dateComponents([.year, .month, .day], from: endDay)
        let endDayInEndCalendar = endCalendar.date(from: endDayComponents) ?? endDay
        var merged = merge(time: endTime, into: endDayInEndCalendar, calendar: endCalendar)

        if timing.endDate == nil,
           let startTime = effectiveStartTime,
           let candidate = merged,
           candidate <= startTime {
            merged = endCalendar.date(byAdding: .day, value: 1, to: candidate)
        }

        return merged
    }

    /// Hours after start used when the show has no explicit end time or end date.
    /// Users rarely know real end times; this is an automatic estimate only.
    static let defaultDurationHours = 4

    static func dailyStartTime(on day: Date, timing: ShowTimingFields, calendar: Calendar) -> Date {
        merge(time: timing.startTime, into: day, calendar: calendar) ?? timing.startTime
    }

    /// 多日共用 endTime 钟点；无 endTime 时为当日 start + 默认时长。
    /// 若 end 钟点 ≤ start 钟点，则落到次日（与单日跨午夜规则一致）。
    static func dailyEndTime(on day: Date, timing: ShowTimingFields, calendar: Calendar) -> Date {
        let dayStart = dailyStartTime(on: day, timing: timing, calendar: calendar)
        if let endTime = timing.endTime {
            let endCalendar = timing.endEventCalendar(fallback: calendar)
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
            let endDay = endCalendar.date(from: dayComponents) ?? day
            var merged = merge(time: endTime, into: endDay, calendar: endCalendar) ?? endTime
            if merged <= dayStart {
                merged = endCalendar.date(byAdding: .day, value: 1, to: merged) ?? merged
            }
            return merged
        }
        return calendar.date(byAdding: .hour, value: defaultDurationHours, to: dayStart) ?? dayStart
    }

    private static func effectiveEndBoundary(
        timing: ShowTimingFields,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveEndDate: Date?,
        effectiveEndTime: Date?
    ) -> Date? {
        // Optional end clock (e.g. from parse) wins when present — not a user-required field.
        if let effectiveEndTime {
            return effectiveEndTime
        }

        // Explicit end day without clock (non daily-cycle path): last day ends at next midnight.
        if let effectiveEndDate {
            let endCalendar = timing.endEventCalendar(fallback: calendar)
            let endDayComponents = calendar.dateComponents([.year, .month, .day], from: effectiveEndDate)
            let endDay = endCalendar.date(from: endDayComponents) ?? effectiveEndDate
            return endCalendar.date(byAdding: .day, value: 1, to: endCalendar.startOfDay(for: endDay))
        }

        // Default: start + fixed duration (no user-filled end).
        let start = effectiveStartTime(timing: timing, calendar: calendar)
        return calendar.date(
            byAdding: .hour,
            value: defaultDurationHours,
            to: start
        )
    }

    private static func merge(time: Date, into day: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        guard var merged = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) else {
            return nil
        }

        if let nanosecond = components.nanosecond, nanosecond > 0 {
            merged = calendar.date(byAdding: .nanosecond, value: nanosecond, to: merged) ?? merged
        }

        return merged
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func countdownCopy(
        kind: CurrentShowTimeKind,
        dayDistance: Int,
        startTime: Date?,
        endBoundary: Date?,
        now: Date,
        retentionDays: Int,
        calendar: Calendar
    ) -> (text: String, number: String, unit: String, helper: String) {
        switch kind {
        case .canceled:
            let copy = BSLocalization.text("这场现场已取消，记录仍会留在我的现场。")
            return (copy, "-", BSLocalization.text("已取消"), copy)
        case .postponed:
            let copy = BSLocalization.text("新的日期还没确定，倒计时先暂停。")
            return (copy, "-", BSLocalization.text("待定"), copy)
        case .before:
            return (
                BSLocalization.format("还有 %lld 天", Int64(dayDistance)),
                "\(dayDistance)",
                BSLocalization.text("天"),
                BSLocalization.text("慢慢进入状态")
            )
        case .today:
            if let startTime, now < startTime {
                let parts = positiveTimeParts(from: now, to: startTime, calendar: calendar)
                return (
                    BSLocalization.format("还有 %lld %@", Int64(parts.value), parts.unit),
                    "\(parts.value)",
                    parts.unit,
                    BSLocalization.text("出门之前，再确认一下")
                )
            }

            if let endBoundary, now < endBoundary, startTime != nil {
                return (
                    BSLocalization.text("正在现场"),
                    BSLocalization.text("正在"),
                    BSLocalization.text("现场"),
                    BSLocalization.text("这场还没有真正结束")
                )
            }

            return (
                BSLocalization.text("今天开场"),
                "0",
                BSLocalization.text("今天"),
                BSLocalization.text("出门之前，再确认一下")
            )
        case .dayEnded:
            let helper: String
            if let startTime,
               let nextStart = calendar.date(byAdding: .day, value: 1, to: startTime) {
                let components = calendar.dateComponents([.hour, .minute], from: nextStart)
                let clock = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
                helper = BSLocalization.format("明天 %@ 再开", clock)
            } else {
                helper = BSLocalization.text("明天再开")
            }
            return (
                BSLocalization.text("今日已落幕"),
                BSLocalization.text("今日"),
                BSLocalization.text("已落幕"),
                helper
            )
        case .postShow:
            let elapsedParts = endBoundary.map {
                positiveTimeParts(from: $0, to: now, calendar: calendar)
            }
            let remainingText: String
            if let endBoundary,
               let retentionEnd = calendar.date(byAdding: .day, value: retentionDays, to: endBoundary) {
                remainingText = BSLocalization.format(
                    "停留期还剩 %@",
                    remainingTimeText(from: now, to: retentionEnd, calendar: calendar)
                )
            } else {
                remainingText = BSLocalization.text("这场还会在这里停留")
            }
            let helper = endBoundary.map {
                "\(endBoundaryText(for: $0, calendar: calendar)) · \(remainingText)"
            } ?? remainingText

            if let elapsedParts, elapsedParts.totalHours < 1 {
                return (
                    BSLocalization.text("散场后停留期"),
                    BSLocalization.text("刚"),
                    BSLocalization.text("散场"),
                    helper
                )
            }

            if let elapsedParts, elapsedParts.totalHours < 24 {
                return (
                    BSLocalization.text("散场后停留期"),
                    "\(elapsedParts.totalHours)",
                    BSLocalization.text("小时前"),
                    helper
                )
            }

            let elapsedDays = max(0, calendar.dateComponents([.day], from: endBoundary ?? now, to: now).day ?? 0)
            return (
                BSLocalization.text("散场后停留期"),
                "\(elapsedDays)",
                BSLocalization.text("天前"),
                helper
            )
        case .ended:
            return (
                BSLocalization.text("已结束"),
                "-",
                BSLocalization.text("已结束"),
                BSLocalization.text("这场已结束")
            )
        }
    }

    private static func endBoundaryText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return BSLocalization.format(
            "%lld月%lld日 %@ 结束",
            Int64(month),
            Int64(day),
            String(format: "%02d:%02d", hour, minute)
        )
    }

    private static func positiveTimeParts(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> (value: Int, unit: String, totalHours: Int) {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let totalHours = seconds / 3_600
        if totalHours >= 1 {
            return (totalHours, BSLocalization.text("小时"), totalHours)
        }

        return (max(1, seconds / 60), BSLocalization.text("分钟"), totalHours)
    }

    private static func remainingTimeText(from start: Date, to end: Date, calendar: Calendar) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return BSLocalization.format("%lld 天 %lld 小时", Int64(days), Int64(hours))
        }
        if hours > 0 {
            return BSLocalization.format("%lld 小时", Int64(hours))
        }
        return BSLocalization.text("不到 1 小时")
    }
}
