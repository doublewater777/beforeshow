import CloudKit
import CryptoKit
import Foundation
import PostHog

/// One explicit action; background discovery and previews do not create attempts.
@MainActor
final class CompanionAnalyticsAttempt {
    enum Operation: String {
        case invitation = "companion_invitation"
        case share = "companion_share"
        case join = "companion_join"
    }

    enum Outcome: String {
        case succeeded, failed, canceled
    }

    private let operation: Operation
    private let source: String
    private let attemptID = UUID().uuidString
    private let started = ContinuousClock.now
    private var finished = false
    var stage = "validation"
    private var sessionID: String?

    init(_ operation: Operation, source: String, sessionRecordName: String? = nil) {
        self.operation = operation
        self.source = source
        linkSession(sessionRecordName)
        capture("started")
    }

    func linkSession(_ recordName: String?) {
        guard let recordName, !recordName.isEmpty else { return }
        // Session names are random UUIDs. Exclude owner identity, URL and share token.
        sessionID = SHA256.hash(data: Data("beforeshow-companion-v1:\(recordName)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func finish(_ outcome: Outcome, error: Error? = nil, errorCategory: String? = nil) {
        guard !finished else { return }
        finished = true
        let elapsed = started.duration(to: .now).components
        var properties: [String: Any] = [
            "outcome": outcome.rawValue,
            "stage": stage,
            "duration_ms": max(0, Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        ]
        if let errorCategory {
            properties["error_category"] = errorCategory
        } else if let error {
            properties["error_category"] = category(for: error)
        }
        capture("finished", properties: properties)
    }

    /// UIActivityViewController completion is an OS acknowledgement, not a join.
    func finishSystemShare(completed: Bool, error: Error?) {
        stage = "system_completion"
        if let error {
            finish(.failed, error: error)
        } else {
            finish(completed ? .succeeded : .canceled)
        }
    }

    private func capture(_ suffix: String, properties: [String: Any] = [:]) {
        var properties = properties
        properties["attempt_id"] = attemptID
        properties["source"] = source
        if let sessionID { properties["session_id"] = sessionID }
        PostHogSDK.shared.capture("\(operation.rawValue)_\(suffix)", properties: properties)
    }

    private func category(for error: Error) -> String {
        if error is CancellationError { return "task_canceled" }
        if let persisted = error as? CompanionPersistedShareError {
            return category(for: persisted.underlying)
        }
        if error is ShowCompanionMutationError { return "conflict" }
        let sharing: CompanionSharingError?
        if error is CKError {
            sharing = CloudKitCompanionSharingService.mapError(
                error, fallback: operation == .join ? .acceptFailed : .sharePreparationFailed
            )
        } else {
            sharing = error as? CompanionSharingError
        }
        switch sharing {
        case .iCloudAccountUnavailable: return "icloud_account_unavailable"
        case .networkFailure: return "network_failure"
        case .sharePreparationFailed: return "share_preparation_failed"
        case .acceptFailed: return "accept_failed"
        case .sessionNotFound: return "session_not_found"
        case .invalidPayload: return "invalid_payload"
        case .permissionDenied: return "permission_denied"
        case .conflict: return "conflict"
        case .statusSyncPending: return "status_sync_pending"
        case nil:
            return stage.hasPrefix("local_") ? "local_persistence" : "unknown"
        }
    }
}
