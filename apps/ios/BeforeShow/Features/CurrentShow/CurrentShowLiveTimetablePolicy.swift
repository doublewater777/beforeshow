import Foundation

enum CurrentShowLiveTimetablePolicy {
    static func resolve(
        for show: Show,
        now: Date,
        calendar: Calendar = .current
    ) -> LiveModeState? {
        guard let timetable = show.timetable,
              show.endedAt == nil,
              show.wasAddedAsHistorical != true,
              show.changeStatus != .canceled,
              !(show.changeStatus == .postponed && show.postponedDate == nil) else {
            return nil
        }
        var eventCalendar = calendar
        eventCalendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? calendar.timeZone
        let state = LiveModeStateEngine.calculate(
            days: LiveModeStateEngine.buildInputs(from: timetable),
            now: now
        )
        switch state.phase {
        case .active, .dayEnded:
            return state
        case .upcoming(let first):
            return eventCalendar.isDate(first, inSameDayAs: now) ? state : nil
        case .fullyEnded:
            guard let finalEnd = timetable.orderedDays.flatMap(\.performances).map(\.endsAt).max() else {
                return nil
            }
            // Keep the finale through the overnight wrap-up, then return to
            // the regular home at the festival's next 06:00 boundary.
            return FestivalDay.distance(from: finalEnd, to: now, calendar: eventCalendar) == 0 ? state : nil
        }
    }
}
