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

        return now >= CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: eventCalendar)
    }
}

extension CurrentShowEndPolicy {
    /// Once the end passes, the show ends there without asking: the filled-in end time, or the
    /// estimate from the start. Only a show with no end to work out is left for the user to confirm.
    static func automaticEnd(
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard show.endedAt == nil else { return nil }
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let state = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard state.kind == .postShow || state.kind == .ended,
              let end = state.endBoundary ?? state.effectiveEndTime,
              isValidConfirmedEnd(end, for: show, now: now, calendar: eventCalendar) else { return nil }
        return end
    }
}
