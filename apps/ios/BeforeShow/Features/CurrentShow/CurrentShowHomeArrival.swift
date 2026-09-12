import Foundation

struct CurrentShowHomeArrival: Hashable {
    enum Phase: Hashable {
        case prepared
        case animating
    }

    let showID: UUID
    var phase: Phase
}

enum CurrentShowHomeArrivalPolicy {
    static func shouldAnimate(newShowID: UUID, currentShowID: UUID?) -> Bool {
        newShowID == currentShowID
    }
}

struct CurrentShowHomeArrivalFlags: Equatable {
    var hasArrivedHero: Bool
    var hasArrivedCountdown: Bool
    var hasArrivedActions: Bool

    static let arrived = CurrentShowHomeArrivalFlags(
        hasArrivedHero: true,
        hasArrivedCountdown: true,
        hasArrivedActions: true
    )

    static let prepared = CurrentShowHomeArrivalFlags(
        hasArrivedHero: false,
        hasArrivedCountdown: false,
        hasArrivedActions: false
    )

    var isPreparedForAnimation: Bool {
        !hasArrivedHero && !hasArrivedCountdown && !hasArrivedActions
    }
}

/// Parent-owned lifecycle for the one-shot Current Show arrival.
///
/// A Current identity change only creates `.prepared`. The parent may move to
/// `.animating` after the child explicitly reports that its three visual flags
/// consumed the prepared state. This prevents `.prepared` from being skipped in
/// the same SwiftUI update cycle as a visible A → B switch.
struct CurrentShowHomeArrivalLifecycle: Equatable {
    private(set) var arrival: CurrentShowHomeArrival?
    private(set) var preparedShowID: UUID?
    private(set) var observedShowID: UUID?
    private(set) var hasObservedIdentity = false

    mutating func observeCurrentShow(_ newShowID: UUID?) {
        let previousShowID = observedShowID
        observedShowID = newShowID

        guard hasObservedIdentity else {
            hasObservedIdentity = true
            return
        }
        guard previousShowID != newShowID else { return }

        preparedShowID = nil
        guard let newShowID else {
            arrival = nil
            return
        }
        arrival = CurrentShowHomeArrival(showID: newShowID, phase: .prepared)
    }

    mutating func childDidPrepare(showID: UUID) {
        guard arrival == CurrentShowHomeArrival(showID: showID, phase: .prepared) else { return }
        preparedShowID = showID
    }

    @discardableResult
    mutating func beginAnimationIfPossible(
        currentShowID: UUID?,
        isVisible: Bool
    ) -> Bool {
        guard isVisible,
              let arrival,
              arrival.phase == .prepared,
              arrival.showID == currentShowID,
              preparedShowID == arrival.showID else {
            return false
        }

        self.arrival = CurrentShowHomeArrival(showID: arrival.showID, phase: .animating)
        return true
    }

    mutating func finish(showID: UUID) {
        guard arrival?.showID == showID else { return }
        arrival = nil
        preparedShowID = nil
    }
}

enum CurrentShowHomeVisibilityPolicy {
    static func isVisible(
        tabIsActive: Bool,
        sceneIsActive: Bool,
        featurePresentationActive: Bool,
        homePresentationActive: Bool,
        managementPresentationActive: Bool
    ) -> Bool {
        tabIsActive
            && sceneIsActive
            && !featurePresentationActive
            && !homePresentationActive
            && !managementPresentationActive
    }
}
