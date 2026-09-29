import Foundation

enum CompanionPendingInviteFailureAction: Equatable {
    case discardCurrentAndContinue
    case discardCurrent
    case retainCurrentForRetry

    var discardsCurrent: Bool { self != .retainCurrentForRetry }
    var continues: Bool { self == .discardCurrentAndContinue }
}

/// Sequencing policy for the durable companion-invite inbox.
/// Terminal invitation failures must not strand later invitations, while retryable
/// infrastructure failures keep the visible invitation in place for another attempt.

struct CompanionPendingInvitePresentationGate: Equatable {
    private(set) var isAwaitingDismissal = false

    mutating func resolvedCurrentPresentation() {
        isAwaitingDismissal = true
    }

    mutating func didDismissCurrentPresentation() -> Bool {
        guard isAwaitingDismissal else { return false }
        isAwaitingDismissal = false
        return true
    }
}

enum CompanionPendingInviteDrainPolicy {
    static func action(
        for error: CompanionSharingError?,
        remainingInviteCount: Int
    ) -> CompanionPendingInviteFailureAction {
        guard let error else { return .retainCurrentForRetry }

        switch error {
        case .sessionNotFound, .invalidPayload, .permissionDenied:
            return remainingInviteCount > 0 ? .discardCurrentAndContinue : .discardCurrent
        case .iCloudAccountUnavailable,
             .networkFailure,
             .sharePreparationFailed,
             .acceptFailed,
             .conflict,
             .statusSyncPending:
            return .retainCurrentForRetry
        }
    }

    static func shouldContinue(remainingInviteCount: Int) -> Bool {
        remainingInviteCount > 0
    }
}
