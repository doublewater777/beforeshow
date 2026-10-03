import CloudKit
import PostHog

/// Scope diagnostics to an explicit user action; background work has no context.
enum CompanionCloudDiagnostics {
    enum Stage: String, Sendable {
        case accountCheck = "account_check"
        case zoneCreate = "zone_create"
        case zoneFetch = "zone_fetch"
        case invitationSave = "invitation_save"
        case shareLoad = "share_load"
        case sharePermissionSave = "share_permission_save"
        case shareURL = "share_url"
        case metadataLoad = "metadata_load"
        case shareAccept = "share_accept"
        case acceptedRootLoad = "accepted_root_load"
    }

    struct Context: Sendable {
        let attemptID: String
        let operation: String
        let source: String

        func report(_ error: Error, stage: Stage) {
            guard let error = error as? CKError else { return }
            var properties: [String: Any] = [
                "attempt_id": attemptID,
                "operation": operation,
                "source": source,
                "stage": stage.rawValue,
                "cloudkit_error_code": error.code.rawValue
            ]
            // Only numeric codes, never record IDs, URLs, descriptions or userInfo.
            let partialCodes = Set((error.partialErrorsByItemID ?? [:]).values
                .compactMap { ($0 as? CKError)?.code.rawValue }).sorted()
            if !partialCodes.isEmpty { properties["cloudkit_partial_error_codes"] = partialCodes }
            PostHogSDK.shared.capture("companion_cloud_request_failed", properties: properties)
        }
    }

    @TaskLocal static var context: Context?

    static func report(_ error: Error, stage: Stage) {
        context?.report(error, stage: stage)
    }
}
