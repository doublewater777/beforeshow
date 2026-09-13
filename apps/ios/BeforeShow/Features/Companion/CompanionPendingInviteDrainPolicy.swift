import Foundation

enum CompanionPendingInviteFailureAction: Equatable {
    case discardCurrentAndContinue
    case discardCurrent
    case retainCurrentForRetry
}

/// Sequencing policy for the durable companion-invite inbox.
/// Terminal invitation failures must not strand later invitations, while retryable
/// infrastructure failures keep the visible invitation in place for another attempt.
enum CompanionPendingInviteDrainPolicy {
    static func action(
        for error: CompanionSharingError?,
        remainingInviteCount: Int
    ) -> CompanionPendingInviteFailureAction {
        switch error {
        case .acceptFailed, .sessionNotFound, .invalidPayload, .permissionDenied:
            return remainingInviteCount > 0 ? .discardCurrentAndContinue : .discardCurrent
        case .iCloudAccountUnavailable,
             .networkFailure,
             .sharePreparationFailed,
             .conflict,
             .statusSyncPending,
             nil:
            return .retainCurrentForRetry
        }
    }

    static func shouldContinue(remainingInviteCount: Int) -> Bool {
        remainingInviteCount > 0
    }
}
