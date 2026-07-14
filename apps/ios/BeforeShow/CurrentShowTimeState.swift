import Foundation

enum CurrentShowTimeKind: Equatable {
    case before
    case today
    case postShow
    case ended
    case canceled
    case postponed
}

/// Phase / clocks / countdown for a 现场. Presentation layout lives in views, not here.
struct CurrentShowTimeState: Equatable {
    static let defaultRetentionDays = 3

    let kind: CurrentShowTimeKind
    let dayDistance: Int
    let retentionDays: Int
    let effectiveDate: Date
    let effectiveEndDate: Date?
    let effectiveStartTime: Date?
    let effectiveEndTime: Date?
    let hasKnownEffectiveDate: Bool
    let isDatedPostponement: Bool
    let countdownText: String
    let countdownNumber: String
    let countdownUnit: String
    let helperText: String

    init(
        show: Show,
        calendar: Calendar = .current,
        now: Date = Date(),
        retentionDays: Int = Self.defaultRetentionDays
    ) {
        self.retentionDays = retentionDays
        self.hasKnownEffectiveDate = !(show.changeStatus == .postponed && show.postponedDate == nil)
        self.isDatedPostponement = show.changeStatus == .postponed && show.postponedDate != nil
        self.effectiveDate = show.effectiveDate
        self.effectiveEndDate = hasKnownEffectiveDate
            ? Self.effectiveEndDate(for: show, calendar: calendar)
            : nil
        self.effectiveStartTime = hasKnownEffectiveDate
            ? Self.effectiveStartTime(for: show, calendar: calendar)
            : nil
        self.effectiveEndTime = hasKnownEffectiveDate
            ? Self.effectiveEndTime(
                for: show,
                calendar: calendar,
                effectiveDate: show.effectiveDate,
                effectiveStartTime: Self.effectiveStartTime(for: show, calendar: calendar)
            )
            : nil

        let today = calendar.startOfDay(for: now)
        let showDay = calendar.startOfDay(for: effectiveDate)
        let days = calendar.dateComponents([.day], from: today, to: showDay).day ?? 0
        self.dayDistance = days

        let endBoundary = hasKnownEffectiveDate
            ? Self.effectiveEndBoundary(
                for: show,
                calendar: calendar,
                effectiveDate: effectiveDate,
                effectiveEndDate: effectiveEndDate,
                effectiveEndTime: effectiveEndTime
            )
            : nil

        let resolvedKind: CurrentShowTimeKind
        if show.changeStatus == .canceled {
            resolvedKind = .canceled
        } else if !hasKnownEffectiveDate {
            resolvedKind = .postponed
        } else if today < showDay {
            resolvedKind = .before
        } else if let endBoundary, now < endBoundary {
            resolvedKind = .today
        } else if let retentionEnd = endBoundary.flatMap({ calendar.date(byAdding: .day, value: retentionDays, to: $0) }),
                  now < retentionEnd {
            resolvedKind = .postShow
        } else {
            resolvedKind = .ended
        }
        self.kind = resolvedKind

        let countdown = Self.countdownCopy(
            kind: resolvedKind,
            dayDistance: days,
            startTime: effectiveStartTime,
            endBoundary: endBoundary,
            now: now,
            retentionDays: retentionDays,
            calendar: calendar
        )
        self.countdownText = countdown.text
        self.countdownNumber = countdown.number
        self.countdownUnit = countdown.unit
        self.helperText = countdown.helper
    }

    var isAutomaticallySelectable: Bool {
        switch kind {
        case .before, .today, .postShow:
            return true
        case .ended, .canceled, .postponed:
            return false
        }
    }

    var isEndedFallbackCandidate: Bool {
        hasKnownEffectiveDate && kind != .canceled && dayDistance < 0
    }

    var canScheduleNotifications: Bool {
        hasKnownEffectiveDate && kind != .canceled
    }

    var title: String {
        switch kind {
        case .before: return "开场前"
        case .today: return "今天开场"
        case .postShow: return "散场后"
        case .ended: return "已结束"
        case .canceled: return "已取消"
        case .postponed: return "时间待定"
        }
    }

    var statusText: String {
        if kind == .canceled {
            return "已取消"
        }
        if !hasKnownEffectiveDate {
            return "已延期，时间待定"
        }
        if isDatedPostponement {
            return "已延期"
        }

        switch kind {
        case .today:
            return "当天"
        case .postShow, .ended:
            return "已结束"
        case .before:
            return "开场前"
        case .canceled:
            return "已取消"
        case .postponed:
            return "已延期，时间待定"
        }
    }

    static func effectiveStartTime(for show: Show, calendar: Calendar) -> Date {
        guard let merged = merge(time: show.startTime, into: show.effectiveDate, calendar: calendar) else {
            return show.startTime
        }
        return merged
    }

    static func effectiveEndDate(for show: Show, calendar: Calendar) -> Date? {
        guard let endDate = show.endDate else {
            return nil
        }
        guard let postponedDate = show.postponedDate else {
            return endDate
        }

        let originalStartDay = calendar.startOfDay(for: show.date)
        let originalEndDay = calendar.startOfDay(for: endDate)
        let dayOffset = calendar.dateComponents([.day], from: originalStartDay, to: originalEndDay).day ?? 0
        return calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: postponedDate)) ?? endDate
    }

    static func effectiveEndTime(
        for show: Show,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveStartTime: Date?
    ) -> Date? {
        guard let endTime = show.endTime else {
            return nil
        }

        let endDay = effectiveEndDate(for: show, calendar: calendar) ?? effectiveDate
        var merged = merge(time: endTime, into: endDay, calendar: calendar)

        if show.endDate == nil,
           let startTime = effectiveStartTime,
           let candidate = merged,
           candidate <= startTime {
            merged = calendar.date(byAdding: .day, value: 1, to: candidate)
        }

        return merged
    }

    /// Hours after start used when the show has no explicit end time.
    /// Users rarely know real end times; this is an automatic estimate only.
    static func defaultDurationHours(for type: ShowType) -> Int {
        switch type {
        case .concert: return 4
        case .livehouse: return 3
        case .musicFestival: return 10
        }
    }

    private static func effectiveEndBoundary(
        for show: Show,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveEndDate: Date?,
        effectiveEndTime: Date?
    ) -> Date? {
        // Optional end clock (e.g. from parse) wins when present — not a user-required field.
        if let effectiveEndTime {
            return effectiveEndTime
        }

        // Multi-day festivals: last day ends at next midnight.
        if let effectiveEndDate {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: effectiveEndDate))
        }

        // Default: start + type duration (no user-filled end time).
        let start = effectiveStartTime(for: show, calendar: calendar)
        return calendar.date(
            byAdding: .hour,
            value: defaultDurationHours(for: show.type),
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
            return ("这场现场已取消，记录仍会留在我的现场。", "-", "已取消", "这场现场已取消，记录仍会留在我的现场。")
        case .postponed:
            return ("新的日期还没确定，倒计时先暂停。", "-", "待定", "新的日期还没确定，倒计时先暂停。")
        case .before:
            return ("还有 \(dayDistance) 天", "\(dayDistance)", "天", "慢慢进入状态")
        case .today:
            if let startTime, now < startTime {
                let parts = positiveTimeParts(from: now, to: startTime, calendar: calendar)
                return ("还有 \(parts.value) \(parts.unit)", "\(parts.value)", parts.unit, "出门之前，再确认一下")
            }

            if let endBoundary, now < endBoundary, startTime != nil {
                return ("正在现场", "正在", "现场", "这场还没有真正结束")
            }

            return ("今天开场", "0", "今天", "出门之前，再确认一下")
        case .postShow:
            let elapsedParts = endBoundary.map {
                positiveTimeParts(from: $0, to: now, calendar: calendar)
            }
            let remainingText: String
            if let endBoundary,
               let retentionEnd = calendar.date(byAdding: .day, value: retentionDays, to: endBoundary) {
                remainingText = "停留期还剩 \(remainingTimeText(from: now, to: retentionEnd, calendar: calendar))"
            } else {
                remainingText = "这场还会在这里停留"
            }
            let helper = endBoundary.map {
                "\(endBoundaryText(for: $0, calendar: calendar)) · \(remainingText)"
            } ?? remainingText

            if let elapsedParts, elapsedParts.totalHours < 1 {
                return ("散场后停留期", "刚", "散场", helper)
            }

            if let elapsedParts, elapsedParts.totalHours < 24 {
                return ("散场后停留期", "\(elapsedParts.totalHours)", "小时前", helper)
            }

            let elapsedDays = max(0, calendar.dateComponents([.day], from: endBoundary ?? now, to: now).day ?? 0)
            return ("散场后停留期", "\(elapsedDays)", "天前", helper)
        case .ended:
            return ("已结束", "-", "已结束", "记忆会留在这里")
        }
    }

    private static func endBoundaryText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(month)月\(day)日 \(String(format: "%02d:%02d", hour, minute)) 结束"
    }

    private static func positiveTimeParts(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> (value: Int, unit: String, totalHours: Int) {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let totalHours = seconds / 3_600
        if totalHours >= 1 {
            return (totalHours, "小时", totalHours)
        }

        return (max(1, seconds / 60), "分钟", totalHours)
    }

    private static func remainingTimeText(from start: Date, to end: Date, calendar: Calendar) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "\(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "\(hours) 小时"
        }
        return "不到 1 小时"
    }
}
