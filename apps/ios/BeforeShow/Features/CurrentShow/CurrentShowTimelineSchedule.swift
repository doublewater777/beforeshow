import SwiftUI

/// Hidden and background home pages keep their state without scheduling ticks.
struct CurrentShowTimelineSchedule: TimelineSchedule {
    let isActive: Bool

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        guard isActive else { return AnySequence([startDate]) }
        return AnySequence(
            PeriodicTimelineSchedule(from: startDate, by: 1)
                .entries(from: startDate, mode: mode)
        )
    }
}
