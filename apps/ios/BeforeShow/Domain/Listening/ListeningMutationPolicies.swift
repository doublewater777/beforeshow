import Foundation

enum ListeningMutationError: Error, Equatable {
    case wantsLiveFrozen(UUID)
}

enum ListeningShowStartPolicy {
    static func effectiveOpeningStart(show: Show) -> Date? {
        guard !(show.changeStatus == .postponed && show.postponedDate == nil) else {
            return nil
        }
        return CurrentShowTimeState.effectiveStartTime(
            for: show,
            calendar: show.timingCalendar()
        )
    }
}

enum WantsLivePolicy {
    static func isMutable(show: Show, now: Date = Date()) -> Bool {
        guard let effectiveStart = ListeningShowStartPolicy.effectiveOpeningStart(show: show) else {
            return true
        }
        return now < effectiveStart
    }
}
