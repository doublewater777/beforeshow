import Foundation
import SwiftData

/// Pure policy: which scheduled, not-yet-ended shows come after the current one.
enum CurrentShowFollowUpPolicy {
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
                let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
                return start > now
            }
            .sorted {
                CurrentShowTimeState.effectiveStartTime(for: $0, calendar: calendar)
                    < CurrentShowTimeState.effectiveStartTime(for: $1, calendar: calendar)
            }
    }
}
