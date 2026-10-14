import Foundation

/// App 侧便捷入口：`Show`(@Model) → 纯值 `ShowTimingFields` → 共享倒计时核。
/// widget extension 只编译 Shared，看不到本文件。
extension Show {
    var lifecycleTimetable: Timetable? {
        guard let timetable, !timetable.needsDateConfirmation, timetable.matchesDates(of: self),
              changeStatus != .canceled,
              !(changeStatus == .postponed && postponedDate == nil) else { return nil }
        return timetable
    }

    var timingFields: ShowTimingFields {
        var timing = declaredTimingFields
        if let timetable = lifecycleTimetable {
            timing.sessions = timetable.orderedDays.compactMap { day in
                guard let start = day.performances.map(\.startsAt).min(),
                      let end = day.performances.map(\.endsAt).max() else { return nil }
                return ShowSessionTiming(date: day.date, startsAt: start, endsAt: end)
            }
            timing.sessionTimeZoneIdentifier = timetable.timeZoneIdentifier
        }
        return timing
    }

    var declaredTimingFields: ShowTimingFields {
        ShowTimingFields(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            timeZoneSecondsFromGMT: timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            endedAt: endedAt,
            postponedDate: postponedDate,
            changeStatus: changeStatus
        )
    }

    /// Aligns the show's date and times to match the timetable's schedule.
    func alignDate(with timetable: Timetable) {
        guard let firstDay = timetable.orderedDays.first else { return }
        let cal = timingCalendar()
        let oldStart = cal.startOfDay(for: effectiveDate)
        let newStart = cal.startOfDay(for: firstDay.date)
        let offset = cal.dateComponents([.day], from: oldStart, to: newStart).day ?? 0
        if offset != 0 {
            if let newDate = cal.date(byAdding: .day, value: offset, to: date) {
                date = newDate
            }
            if let newStartTime = cal.date(byAdding: .day, value: offset, to: startTime) {
                startTime = newStartTime
            }
            if let et = endTime, let newEndTime = cal.date(byAdding: .day, value: offset, to: et) {
                endTime = newEndTime
            }
        }
        if timetable.orderedDays.count > 1, let lastDay = timetable.orderedDays.last {
            endDate = lastDay.date
        } else if let end = endDate {
            if offset != 0, let newEnd = cal.date(byAdding: .day, value: offset, to: end) {
                endDate = newEnd
            }
            if let currentEnd = endDate, !cal.isDate(firstDay.date, inSameDayAs: currentEnd) {
                endDate = endTime != nil ? date : nil
            }
        }
        _ = timetable.confirmDates(for: self)
        discardConfirmedEndBeforeEffectiveStart()
        touch()
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
        isMultiDayDailyCycle(timing: show.timingFields, calendar: show.timingFields.eventCalendar(fallback: calendar))
    }

    static func effectiveStartTime(for show: Show, calendar: Calendar) -> Date {
        effectiveStartTime(timing: show.timingFields, calendar: show.timingFields.eventCalendar(fallback: calendar))
    }

    /// Earliest user-confirmable end: the final daily session start for a
    /// multi-day cycle, otherwise the show's effective start.
    static func minimumConfirmableEnd(for show: Show, calendar: Calendar) -> Date {
        let eventCalendar = show.timingFields.eventCalendar(fallback: calendar)
        if let finalStart = show.lifecycleTimetable?.orderedDays.last(where: { !$0.performances.isEmpty })?
            .performances.map(\.startsAt).min() {
            return finalStart
        }
        guard isMultiDayDailyCycle(for: show, calendar: eventCalendar),
              let finalDay = effectiveEndDate(for: show, calendar: eventCalendar) else {
            return effectiveStartTime(for: show, calendar: eventCalendar)
        }
        return dailyStartTime(on: finalDay, show: show, calendar: eventCalendar)
    }

    static func effectiveEndDate(for show: Show, calendar: Calendar) -> Date? {
        effectiveEndDate(timing: show.timingFields, calendar: show.timingFields.eventCalendar(fallback: calendar))
    }

    static func effectiveEndTime(
        for show: Show,
        calendar: Calendar,
        effectiveDate: Date,
        effectiveStartTime: Date?
    ) -> Date? {
        effectiveEndTime(
            timing: show.timingFields,
            calendar: show.timingFields.eventCalendar(fallback: calendar),
            effectiveDate: effectiveDate,
            effectiveStartTime: effectiveStartTime
        )
    }

    static func dailyStartTime(on day: Date, show: Show, calendar: Calendar) -> Date {
        dailyStartTime(on: day, timing: show.timingFields, calendar: show.timingFields.eventCalendar(fallback: calendar))
    }

    static func dailyEndTime(on day: Date, show: Show, calendar: Calendar) -> Date {
        dailyEndTime(on: day, timing: show.timingFields, calendar: show.timingFields.eventCalendar(fallback: calendar))
    }
}
