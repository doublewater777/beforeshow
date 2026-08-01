import Foundation

/// App 侧便捷入口：`Show`(@Model) → 纯值 `ShowTimingFields` → 共享倒计时核。
/// widget extension 只编译 Shared，看不到本文件。
extension Show {
    var timingFields: ShowTimingFields {
        ShowTimingFields(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            endedAt: endedAt,
            postponedDate: postponedDate,
            changeStatus: changeStatus
        )
    }
}

extension CurrentShowTimeState {
    init(
        show: Show,
        calendar: Calendar = .current,
        now: Date = Date(),
        retentionDays: Int = Self.defaultRetentionDays
    ) {
        self.init(timing: show.timingFields, calendar: calendar, now: now, retentionDays: retentionDays)
    }

    static func isMultiDayDailyCycle(for show: Show, calendar: Calendar) -> Bool {
        isMultiDayDailyCycle(timing: show.timingFields, calendar: calendar)
    }

    static func effectiveStartTime(for show: Show, calendar: Calendar) -> Date {
        effectiveStartTime(timing: show.timingFields, calendar: calendar)
    }

    /// Earliest user-confirmable end: the final daily session start for a
    /// multi-day cycle, otherwise the show's effective start.
    static func minimumConfirmableEnd(for show: Show, calendar: Calendar) -> Date {
        guard isMultiDayDailyCycle(for: show, calendar: calendar),
              let finalDay = effectiveEndDate(for: show, calendar: calendar) else {
            return effectiveStartTime(for: show, calendar: calendar)
        }
        return dailyStartTime(on: finalDay, show: show, calendar: calendar)
    }

    static func effectiveEndDate(for show: Show, calendar: Calendar) -> Date? {
        effectiveEndDate(timing: show.timingFields, calendar: calendar)
    }

    static func effectiveEndTime(
        for show: Show,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveStartTime: Date?
    ) -> Date? {
        effectiveEndTime(
            timing: show.timingFields,
            calendar: calendar,
            effectiveDate: effectiveDate,
            effectiveStartTime: effectiveStartTime
        )
    }

    static func dailyStartTime(on day: Date, show: Show, calendar: Calendar) -> Date {
        dailyStartTime(on: day, timing: show.timingFields, calendar: calendar)
    }

    static func dailyEndTime(on day: Date, show: Show, calendar: Calendar) -> Date {
        dailyEndTime(on: day, timing: show.timingFields, calendar: calendar)
    }
}
