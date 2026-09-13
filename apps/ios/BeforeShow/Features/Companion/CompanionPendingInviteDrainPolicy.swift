import Foundation

/// Pure sequencing rule for the durable companion-invite inbox.
/// Resolving the visible invitation must immediately advance to the next queued item.
enum CompanionPendingInviteDrainPolicy {
    static func shouldContinue(remainingInviteCount: Int) -> Bool {
        remainingInviteCount > 0
    }
}
