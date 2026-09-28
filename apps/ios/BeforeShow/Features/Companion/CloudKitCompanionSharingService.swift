import CloudKit
import Foundation
import os

// MARK: - CloudKit field keys

enum CompanionSessionRecord {
    static let recordType = "CompanionSession"
    static let showID = "showID"
    static let showName = "showName"
    static let showDate = "showDate"
    static let showStartTime = "showStartTime"
    static let showLocation = "showLocation"
    /// Versioned immutable full-show payload captured when the share is first created.
    static let showSnapshotV1 = "showSnapshotV1"
    static let ownerDisplayName = "ownerDisplayName"
    static let participantDisplayName = "participantDisplayName"
    static let status = "status"
    static let createdAt = "createdAt"
    static let acceptedAt = "acceptedAt"
    static let canceledAt = "canceledAt"
}

// MARK: - CloudKit implementation

enum CompanionDebugLog {
    static func write(_ message: String) {
        Logger(subsystem: "com.doublewaterapps.beforeshow", category: "companion")
            .error("\(message, privacy: .public)")
        print("COMPANION \(message)")
    }
}

enum CompanionShareURLRetryPolicy {
    static let delays: [Duration] = [.milliseconds(200), .milliseconds(500), .seconds(1)]
}

struct CloudKitCompanionSharingService: CompanionSharingService {

    private let explicitContainer: CKContainer?

    var container: CKContainer {
        explicitContainer ?? CKContainer(identifier: Self.defaultContainerIdentifier)
    }

    private static let log = Logger(subsystem: "com.doublewaterapps.beforeshow", category: "companion")

    static let defaultContainerIdentifier = "iCloud.com.doublewaterapps.beforeshow"

    init(container: CKContainer? = nil) {
        self.explicitContainer = container
    }

    static func live() -> CloudKitCompanionSharingService {
        CloudKitCompanionSharingService()
    }

    var privateDB: CKDatabase { container.privateCloudDatabase }

    var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func shareWithInvitationURL(_ share: CKShare) async throws -> CKShare {
        if share.url != nil { return share }
        let delays = CompanionShareURLRetryPolicy.delays
        for attempt in 0...delays.count {
            if attempt > 0 { try await Task.sleep(for: delays[attempt - 1]) }
            do {
                guard let candidate = try await privateDB.record(for: share.recordID) as? CKShare else {
                    throw CompanionSharingError.sharePreparationFailed
                }
                if candidate.url != nil {
                    CompanionDebugLog.write("Companion invite stage=share-url ready attempt=\(attempt + 1)")
                    return candidate
                }
            } catch {
                let mapped = Self.mapError(error)
                CompanionDebugLog.write("Companion invite stage=share-url failed: \(mapped)")
                throw mapped
            }
        }
        CompanionDebugLog.write("Companion invite stage=share-url exhausted")
        throw CompanionSharingError.sharePreparationFailed
    }
}
