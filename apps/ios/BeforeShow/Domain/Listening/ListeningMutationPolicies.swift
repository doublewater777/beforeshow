import Foundation

enum ListeningMutationError: Error, Equatable {
    case wantsLiveFrozen(UUID)
}

enum ListeningShowStartPolicy {
    static func effectiveOpeningStart(show: Show) -> Date? {
        guard !(show.changeStatus == .postponed && show.postponedDate == nil) else {
            return nil
        }
        let timing = ShowTimingFields(
            date: show.date,
            startTime: show.startTime,
            endDate: show.endDate,
            endTime: show.endTime,
            timeZoneSecondsFromGMT: show.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: show.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: show.timeZoneIdentifier,
            endTimeZoneIdentifier: show.endTimeZoneIdentifier,
            endedAt: show.endedAt,
            postponedDate: show.postponedDate,
            changeStatus: show.changeStatus
        )
        return CurrentShowTimeState.effectiveStartTime(
            timing: timing,
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
