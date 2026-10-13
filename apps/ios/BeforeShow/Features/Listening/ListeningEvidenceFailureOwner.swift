import Foundation

/// Owns the playback-evidence failure lifecycle for Listening.
///
/// General `errorText` and playback alerts stay on the room coordinator because
/// they are separate user-facing surfaces. This type only tracks whether evidence
/// persistence currently owns the general alert, so retries cannot clobber an
/// unrelated error or re-present a dismissed one without cause.
@MainActor
struct ListeningEvidenceFailureOwner {
    private(set) var retryPending = false
    private var alertShown = false
    private var ownsGeneralError = false

    mutating func present(
        into generalError: inout String?,
        message: String,
        representDismissedAlert: Bool
    ) {
        retryPending = true
        if generalError == nil, representDismissedAlert || !alertShown {
            alertShown = true
            generalError = message
            ownsGeneralError = true
        }
    }

    mutating func recover(
        generalError: inout String?,
        expectedMessage: String
    ) {
        guard retryPending || alertShown || ownsGeneralError else { return }
        retryPending = false
        alertShown = false
        if ownsGeneralError, generalError == expectedMessage {
            generalError = nil
        }
        ownsGeneralError = false
    }

    mutating func noteGeneralDismissed() {
        ownsGeneralError = false
    }
}
