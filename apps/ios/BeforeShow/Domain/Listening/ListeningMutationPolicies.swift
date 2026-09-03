import Foundation

enum ListeningMutationError: Error, Equatable {
    case wantsLiveFrozen(UUID)
}

enum WantsLivePolicy {
    static func isMutable(show: Show, now: Date = Date()) -> Bool {
        let timeState = CurrentShowTimeState(show: show, now: now)
        guard let effectiveStart = timeState.effectiveStartTime else {
            return true
        }
        return now < effectiveStart
    }
}
