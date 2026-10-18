import Foundation
import SwiftData

/// Pure policy: other scheduled shows that are live now or have not yet started.
enum CurrentShowFollowUpPolicy {
    /// The first actual opening, not the next session when a festival pauses overnight.
    /// Filtering, ordering and row countdowns must use the same instant.
    static func firstStart(for show: Show, calendar: Calendar = .current) -> Date {
        let timing = show.timingFields
        let eventCalendar = timing.eventCalendar(fallback: calendar)
        return timing.resolvedSessions(calendar: eventCalendar).first?.startsAt
            ?? CurrentShowTimeState.effectiveStartTime(timing: timing, calendar: eventCalendar)
    }

    /// A different live show stays in the summary until its scheduled end boundary.
    /// Use the same lifecycle state as the home hero instead of treating every past start as ended.
    static func isLive(_ show: Show, now: Date, calendar: Calendar = .current) -> Bool {
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        return HomeShowPhase(timeState: state, now: now) == .live
    }

    static func laterShows(
        from shows: [Show],
        excluding currentShowID: UUID?,
        now: Date,
        calendar: Calendar = .current
    ) -> [Show] {
        shows
            .filter { show in
                guard show.id != currentShowID,
                      show.changeStatus == .scheduled,
                      show.endedAt == nil else { return false }
                return firstStart(for: show, calendar: calendar) > now
                    || isLive(show, now: now, calendar: calendar)
            }
            .sorted {
                firstStart(for: $0, calendar: calendar)
                    < firstStart(for: $1, calendar: calendar)
            }
    }
}
