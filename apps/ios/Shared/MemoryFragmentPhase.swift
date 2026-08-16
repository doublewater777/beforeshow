import Foundation

/// 记忆碎片在创建时固化的现场位置。外显分组标题固定为这三词。
enum MemoryFragmentPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case before
    case live
    case after

    var title: String {
        switch self {
        case .before: return BSLocalization.text("开场前")
        case .live: return BSLocalization.text("进行中")
        case .after: return BSLocalization.text("散场后")
        }
    }

    /// 时间流组序：散场后 → 进行中 → 开场前。
    static let timelineDisplayOrder: [MemoryFragmentPhase] = [.after, .live, .before]

    /// 用记录时刻对照现场时间边界解析阶段。
    ///
    /// 这是记忆专用规则，不能直接复用首页 `HomeShowPhase`：
    /// 多日现场在“当日结束后、次日开场前”应固化为散场后，而不是开场前。
    /// 取消 / 延期待定等无可靠边界兜底为进行中。
    static func resolved(
        at createdAt: Date,
        timing: ShowTimingFields,
        calendar: Calendar = .current
    ) -> MemoryFragmentPhase {
        if timing.changeStatus == .canceled {
            return .live
        }
        if timing.changeStatus == .postponed && timing.postponedDate == nil {
            return .live
        }

        let eventCalendar = timing.eventCalendar(fallback: calendar)
        let state = CurrentShowTimeState(timing: timing, calendar: eventCalendar, now: createdAt)

        // Manual end: anything at/after endedAt is after.
        if let endedAt = timing.endedAt, createdAt >= endedAt {
            return .after
        }

        if CurrentShowTimeState.isMultiDayDailyCycle(timing: timing, calendar: eventCalendar) {
            return resolveMultiDay(at: createdAt, timing: timing, calendar: eventCalendar)
        }

        guard let start = state.effectiveStartTime else {
            return .live
        }
        if createdAt < start {
            return .before
        }
        if let endBoundary = state.endBoundary {
            return createdAt < endBoundary ? .live : .after
        }
        return .live
    }

    private static func resolveMultiDay(
        at createdAt: Date,
        timing: ShowTimingFields,
        calendar: Calendar
    ) -> MemoryFragmentPhase {
        let firstStart = CurrentShowTimeState.effectiveStartTime(timing: timing, calendar: calendar)
        if createdAt < firstStart {
            return .before
        }

        let firstDay = calendar.startOfDay(for: timing.effectiveDate)
        let lastDay = calendar.startOfDay(
            for: CurrentShowTimeState.effectiveEndDate(timing: timing, calendar: calendar) ?? timing.effectiveDate
        )

        // Walk each daily session until we find where createdAt lands.
        var day = firstDay
        while day <= lastDay {
            let dayStart = CurrentShowTimeState.dailyStartTime(on: day, timing: timing, calendar: calendar)
            let dayEnd = CurrentShowTimeState.dailyEndTime(on: day, timing: timing, calendar: calendar)

            if createdAt < dayStart {
                // After a previous day ended, before this day's start.
                return day == firstDay ? .before : .after
            }
            if createdAt < dayEnd {
                return .live
            }

            // createdAt is at/after this day's end. If there is a next day, keep scanning;
            // otherwise the whole run has finished.
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay <= lastDay else {
                return .after
            }
            day = nextDay
        }

        return .after
    }
}

enum MemoryFragmentRelativeTime {
    static func format(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let diff = max(0, now.timeIntervalSince(date))
        if calendar.isDate(date, inSameDayAs: now) {
            if diff < 60 { return BSLocalization.text("刚刚") }
            if diff < 3_600 {
                return BSLocalization.format("%lld 分钟前", Int64(max(1, Int(diff / 60))))
            }
            return BSLocalization.format("%lld 小时前", Int64(max(1, Int(diff / 3_600))))
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return BSLocalization.format("昨天 %@", clockText(date, calendar: calendar))
        }

        return exact(date, now: now, calendar: calendar)
    }

    static func exact(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = clockText(date, calendar: calendar)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return BSLocalization.format("%lld月%lld日 %@", Int64(month), Int64(day), time)
        }
        let year = calendar.component(.year, from: date)
        return BSLocalization.format("%lld年%lld月%lld日 %@", Int64(year), Int64(month), Int64(day), time)
    }

    private static func clockText(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
