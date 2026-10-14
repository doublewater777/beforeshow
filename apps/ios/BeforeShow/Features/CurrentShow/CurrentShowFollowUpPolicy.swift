import Foundation
import SwiftData

/// Pure policy: which scheduled, not-yet-started shows come after the current one.
enum CurrentShowFollowUpPolicy {
    /// The first actual opening, not the next session when a festival pauses overnight.
    /// Filtering, ordering and row countdowns must use the same instant.
    static func firstStart(for show: Show, calendar: Calendar = .current) -> Date {
        let timing = show.timingFields
        let eventCalendar = timing.eventCalendar(fallback: calendar)
        return timing.resolvedSessions(calendar: eventCalendar).first?.startsAt
            ?? CurrentShowTimeState.effectiveStartTime(timing: timing, calendar: eventCalendar)
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
            }
            .sorted {
                firstStart(for: $0, calendar: calendar)
                    < firstStart(for: $1, calendar: calendar)
            }
    }
}
