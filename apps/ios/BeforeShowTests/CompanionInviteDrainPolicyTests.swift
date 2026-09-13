import XCTest
@testable import BeforeShow

final class CompanionInviteDrainPolicyTests: XCTestCase {
    func testTerminalFailureWithSecondInviteDiscardsCurrentAndAdvances() {
        let terminalErrors: [CompanionSharingError] = [
            .acceptFailed,
            .sessionNotFound,
            .invalidPayload,
            .permissionDenied,
        ]

        for error in terminalErrors {
            XCTAssertEqual(
                CompanionPendingInviteDrainPolicy.action(
                    for: error,
                    remainingInviteCount: 1
                ),
                .discardCurrentAndContinue,
                "A terminal failure must remove A and immediately advance to queued B: \(error)"
            )
        }
    }

    func testRetryableFailureKeepsCurrentInviteAndDoesNotAdvance() {
        let retryableErrors: [CompanionSharingError] = [
            .networkFailure,
            .statusSyncPending,
            .iCloudAccountUnavailable,
            .sharePreparationFailed,
            .conflict,
        ]

        for error in retryableErrors {
            XCTAssertEqual(
                CompanionPendingInviteDrainPolicy.action(
                    for: error,
                    remainingInviteCount: 1
                ),
                .retainCurrentForRetry,
                "A retryable failure must keep A visible for retry instead of advancing to B: \(error)"
            )
        }
    }

    func testTerminalFailureWithoutAnotherInviteOnlyDiscardsCurrent() {
        XCTAssertEqual(
            CompanionPendingInviteDrainPolicy.action(
                for: .permissionDenied,
                remainingInviteCount: 0
            ),
            .discardCurrent
        )
    }

    func testUnknownFailureDispositionIsConservativeAndRetryable() {
        XCTAssertEqual(
            CompanionPendingInviteDrainPolicy.action(
                for: nil,
                remainingInviteCount: 1
            ),
            .retainCurrentForRetry
        )
    }

    func testResolvingFirstOfTwoInvitesImmediatelyAdvancesToSecond() {
        XCTAssertTrue(
            CompanionPendingInviteDrainPolicy.shouldContinue(remainingInviteCount: 1),
            "A+B: after resolving A, B must continue without foreground/relaunch"
        )
    }

    func testResolvingLastInviteStopsDrain() {
        XCTAssertFalse(
            CompanionPendingInviteDrainPolicy.shouldContinue(remainingInviteCount: 0)
        )
    }
}
