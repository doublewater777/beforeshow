import Foundation

/// Pure policy: whether the current 现场 can record a confirmed end time right now.
/// Derives `HomeShowPhase` internally so callers pass time-state once (not phase+timeState).
enum CurrentShowEndPolicy {
    static func isValidConfirmedEnd(
        _ date: Date,
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        return date >= CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: eventCalendar)
            && date <= now
    }

    static func canRecordEnd(
        show: Show,
        timeState: CurrentShowTimeState,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let phase = HomeShowPhase(timeState: timeState, now: now)
        guard show.endedAt == nil else { return false }
        guard phase == .live || timeState.kind == .postShow || timeState.kind == .ended else {
            return false
        }
        guard CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: eventCalendar) else {
            return true
        }
        guard phase == .live else { return true }
        guard let finalDay = timeState.effectiveEndDate else { return false }
        guard let activeStart = timeState.effectiveStartTime else { return false }
        return eventCalendar.isDate(activeStart, inSameDayAs: finalDay)
    }
}
