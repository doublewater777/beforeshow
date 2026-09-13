import XCTest
@testable import BeforeShow

final class CompanionInviteDrainPolicyTests: XCTestCase {
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
