import XCTest
@testable import BeforeShow

@MainActor
final class ListeningEvidenceFailureOwnerTests: XCTestCase {
    func testPresentClaimsEmptyGeneralErrorOnce() {
        var owner = ListeningEvidenceFailureOwner()
        var generalError: String?

        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: true
        )

        XCTAssertEqual(generalError, "保存失败，请重试")
        XCTAssertTrue(owner.retryPending)

        generalError = nil
        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: false
        )
        XCTAssertNil(generalError, "dismissed evidence alert must not reappear without representDismissedAlert")
        XCTAssertTrue(owner.retryPending)
    }

    func testPresentDoesNotStealExistingGeneralError() {
        var owner = ListeningEvidenceFailureOwner()
        var generalError: String? = "unrelated"

        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: true
        )

        XCTAssertEqual(generalError, "unrelated")
        XCTAssertTrue(owner.retryPending)
    }

    func testRecoverClearsOwnedGeneralErrorOnly() {
        var owner = ListeningEvidenceFailureOwner()
        var generalError: String?

        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: true
        )
        owner.recover(generalError: &generalError, expectedMessage: "保存失败，请重试")

        XCTAssertNil(generalError)
        XCTAssertFalse(owner.retryPending)

        generalError = "unrelated"
        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: true
        )
        owner.recover(generalError: &generalError, expectedMessage: "保存失败，请重试")
        XCTAssertEqual(generalError, "unrelated")
        XCTAssertFalse(owner.retryPending)
    }

    func testNoteGeneralDismissedReleasesOwnershipWithoutClearingRetry() {
        var owner = ListeningEvidenceFailureOwner()
        var generalError: String?

        owner.present(
            into: &generalError,
            message: "保存失败，请重试",
            representDismissedAlert: true
        )
        generalError = nil
        owner.noteGeneralDismissed()
        owner.recover(generalError: &generalError, expectedMessage: "保存失败，请重试")

        XCTAssertNil(generalError)
        XCTAssertFalse(owner.retryPending)
    }
}
