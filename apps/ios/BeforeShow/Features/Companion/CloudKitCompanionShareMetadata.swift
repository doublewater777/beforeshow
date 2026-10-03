import CloudKit
import Foundation

private final class CompanionShareMetadataCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CKShare.Metadata, Error>?

    init(_ continuation: CheckedContinuation<CKShare.Metadata, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<CKShare.Metadata, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
        return pending != nil
    }
}

extension CloudKitCompanionSharingService {
    static func fetchMetadataWithRootRecord(
        for shareURL: URL,
        in container: CKContainer = CKContainer(identifier: defaultContainerIdentifier)
    ) async throws -> CKShare.Metadata {
        let diagnostics = CompanionCloudDiagnostics.context
        return try await withCheckedThrowingContinuation { continuation in
            let completion = CompanionShareMetadataCompletion(continuation)
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.shouldFetchRootRecord = true
            operation.qualityOfService = .userInitiated
            operation.timeoutIntervalForRequest = 10
            operation.timeoutIntervalForResource = 15
            operation.perShareMetadataResultBlock = { _, result in
                if completion.finish(result.mapError { Self.mapError($0, fallback: .acceptFailed) }),
                   case .failure(let error) = result {
                    diagnostics?.report(error, stage: .metadataLoad)
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    completion.finish(.failure(CompanionSharingError.acceptFailed))
                case .failure(let error):
                    if completion.finish(.failure(Self.mapError(error, fallback: .acceptFailed))) {
                        diagnostics?.report(error, stage: .metadataLoad)
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if completion.finish(.failure(CompanionSharingError.networkFailure)) {
                    operation.cancel()
                }
            }
            container.add(operation)
        }
    }
}

enum CompanionCloudAcceptRecoveryPolicy {
    static func canRecover(
        after errorCode: CKError.Code?,
        sharedDatabaseConfirmsAcceptedParticipant: Bool
    ) -> Bool {
        guard errorCode == .alreadyShared || errorCode == .serverRejectedRequest else {
            return false
        }
        return sharedDatabaseConfirmsAcceptedParticipant
    }
}

struct CompanionAcceptedShareContext {
    let shareLocator: CompanionRecordLocator
    let record: CKRecord
    let participantDisplayNames: [String]
    let ownerDisplayName: String?
    let acceptedShare: CKShare
}

extension CloudKitCompanionSharingService {
    func metadataIncludingRootRecord(
        _ metadata: CKShare.Metadata
    ) async throws -> CKShare.Metadata {
        if metadata.rootRecord != nil {
            return metadata
        }
        guard let shareURL = metadata.share.url else {
            throw CompanionSharingError.invalidPayload
        }

        return try await Self.fetchMetadataWithRootRecord(for: shareURL, in: container)
    }

    func acceptedShareContext(
        metadata: CKShare.Metadata
    ) async throws -> CompanionAcceptedShareContext {
        try await ensureAccountAvailable()

        let acceptedMetadata = try await metadataIncludingRootRecord(metadata)
        let shareLocator = CompanionRecordLocator(recordID: acceptedMetadata.share.recordID)
        let isOwner = acceptedMetadata.share.currentUserParticipant?.role == .owner
        let acceptedShare: CKShare
        if isOwner {
            acceptedShare = acceptedMetadata.share
        } else {
            do {
                acceptedShare = try await container.accept(acceptedMetadata)
            } catch {
                let errorCode = (error as? CKError)?.code
                guard errorCode == .alreadyShared || errorCode == .serverRejectedRequest else {
                    CompanionCloudDiagnostics.report(error, stage: .shareAccept)
                    throw Self.mapError(error, fallback: .acceptFailed)
                }

                // A failed accept call is recoverable only when the shared database
                // independently proves that this user is already an accepted participant.
                let existing = try? await sharedDB.record(for: shareLocator.recordID) as? CKShare
                let confirmsAcceptedParticipant =
                    existing?.currentUserParticipant?.acceptanceStatus == .accepted
                guard CompanionCloudAcceptRecoveryPolicy.canRecover(
                    after: errorCode,
                    sharedDatabaseConfirmsAcceptedParticipant: confirmsAcceptedParticipant
                ),
                let existing else {
                    CompanionCloudDiagnostics.report(error, stage: .shareAccept)
                    throw Self.mapError(error, fallback: .acceptFailed)
                }
                acceptedShare = existing
            }
        }

        guard let rootID = acceptedMetadata.hierarchicalRootRecordID else {
            throw CompanionSharingError.invalidPayload
        }

        let record: CKRecord
        if isOwner {
            do {
                record = try await privateDB.record(for: rootID)
            } catch {
                if let preloaded = acceptedMetadata.rootRecord {
                    record = preloaded
                } else {
                    CompanionCloudDiagnostics.report(error, stage: .acceptedRootLoad)
                    throw Self.mapError(error, fallback: .acceptFailed)
                }
            }
        } else {
            do {
                // For participants, the root record must be readable from the shared
                // database. Falling back to metadata/private DB would manufacture
                // "accepted" state without proof of share membership.
                record = try await sharedDB.record(for: rootID)
            } catch {
                CompanionCloudDiagnostics.report(error, stage: .acceptedRootLoad)
                throw Self.mapError(error, fallback: .statusSyncPending)
            }
        }

        func leaveShareOrThrowCleanupPending() async throws {
            do {
                _ = try await modifyRecords(
                    in: sharedDB,
                    saving: [],
                    deleting: [shareLocator.recordID]
                )
            } catch {
                let mapped = Self.mapError(error)
                if mapped != .sessionNotFound {
                    throw CompanionSharingError.statusSyncPending
                }
            }
        }

        if let statusRaw = record[CompanionSessionRecord.status] as? String,
           statusRaw == CompanionCloudStatus.canceled.rawValue {
            try await leaveShareOrThrowCleanupPending()
            throw CompanionSharingError.sessionNotFound
        }

        do {
            _ = try Self.snapshot(from: record, shareLocator: shareLocator)
        } catch {
            try await leaveShareOrThrowCleanupPending()
            throw CompanionSharingError.invalidPayload
        }

        return CompanionAcceptedShareContext(
            shareLocator: shareLocator,
            record: record,
            participantDisplayNames: Self.participantNames(from: acceptedShare),
            ownerDisplayName: Self.displayName(for: acceptedMetadata.ownerIdentity),
            acceptedShare: acceptedShare
        )
    }


}
