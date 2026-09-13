import CloudKit
import Foundation

private struct CompanionAcceptedShareContext {
    let shareLocator: CompanionRecordLocator
    let record: CKRecord
    let participantDisplayNames: [String]
    let ownerDisplayName: String?
}

private struct CompanionShareParticipationState {
    let participantDisplayNames: [String]
    let hasAcceptedNonOwner: Bool

    static let empty = CompanionShareParticipationState(
        participantDisplayNames: [],
        hasAcceptedNonOwner: false
    )
}

extension CloudKitCompanionSharingService {
    func previewAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName _: String?
    ) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()

        let previewMetadata = try await metadataIncludingRootRecord(metadata)
        guard let record = previewMetadata.rootRecord else {
            throw CompanionSharingError.invalidPayload
        }
        if let statusRaw = record[CompanionSessionRecord.status] as? String,
           statusRaw == CompanionCloudStatus.canceled.rawValue {
            throw CompanionSharingError.permissionDenied
        }

        let shareLocator = CompanionRecordLocator(recordID: previewMetadata.share.recordID)
        var snapshot = try Self.snapshot(
            from: record,
            shareLocator: shareLocator,
            participantDisplayNames: Self.participantNames(from: previewMetadata.share)
        )
        if snapshot.ownerDisplayName == nil {
            snapshot.ownerDisplayName = Self.displayName(for: previewMetadata.ownerIdentity)
        }
        return snapshot
    }

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName _: String?
    ) async throws -> CompanionSessionSnapshot {
        let context = try await acceptedShareContext(metadata: metadata)

        // Joining a companion invite is represented by CloudKit share acceptance.
        // The root record is a frozen, read-only Show snapshot and is never mutated
        // by participants after they tap the in-app join confirmation.
        var snapshot = try Self.snapshot(
            from: context.record,
            shareLocator: context.shareLocator,
            forcedStatus: .accepted,
            participantDisplayNames: context.participantDisplayNames
        )
        if snapshot.ownerDisplayName == nil {
            snapshot.ownerDisplayName = context.ownerDisplayName
        }
        return snapshot
    }

    private func metadataIncludingRootRecord(
        _ metadata: CKShare.Metadata
    ) async throws -> CKShare.Metadata {
        if metadata.rootRecord != nil {
            return metadata
        }
        guard let shareURL = metadata.share.url else {
            throw CompanionSharingError.invalidPayload
        }

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.shouldFetchRootRecord = true
            operation.qualityOfService = .userInitiated
            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata):
                    continuation.resume(returning: metadata)
                case .failure(let error):
                    continuation.resume(throwing: Self.mapError(error, fallback: .acceptFailed))
                }
            }
            container.add(operation)
        }
    }

    private func acceptedShareContext(
        metadata: CKShare.Metadata
    ) async throws -> CompanionAcceptedShareContext {
        try await ensureAccountAvailable()

        let acceptedMetadata = try await metadataIncludingRootRecord(metadata)
        let shareLocator = CompanionRecordLocator(recordID: acceptedMetadata.share.recordID)
        let acceptedShare: CKShare
        do {
            acceptedShare = try await container.accept(acceptedMetadata)
        } catch {
            let ck = error as? CKError
            if ck?.code != .alreadyShared {
                throw Self.mapError(error, fallback: .acceptFailed)
            }
            do {
                guard let existingShare = try await sharedDB.record(for: shareLocator.recordID) as? CKShare else {
                    throw CompanionSharingError.sessionNotFound
                }
                acceptedShare = existingShare
            } catch {
                throw Self.mapError(error, fallback: .statusSyncPending)
            }
        }

        guard let rootID = acceptedMetadata.hierarchicalRootRecordID else {
            throw CompanionSharingError.invalidPayload
        }

        let record: CKRecord
        do {
            record = try await sharedDB.record(for: rootID)
        } catch {
            throw Self.mapError(error)
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
            throw CompanionSharingError.permissionDenied
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
            ownerDisplayName: Self.displayName(for: acceptedMetadata.ownerIdentity)
        )
    }

    func cancelSession(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?,
        isOwner: Bool
    ) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()

        if isOwner {
            return try await cancelAsOwner(sessionLocator: sessionLocator, shareLocator: shareLocator)
        }
        return try await cancelAsParticipant(sessionLocator: sessionLocator, shareLocator: shareLocator)
    }

    func fetchSession(sessionLocator: CompanionRecordLocator) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()
        let (record, database) = try await fetchSessionRecord(locator: sessionLocator)
        let participation = try await shareParticipationState(for: record, in: database)

        let rootStatus = (record[CompanionSessionRecord.status] as? String)
            .flatMap(CompanionCloudStatus.init(rawValue:))
        let forcedStatus: CompanionCloudStatus?
        if rootStatus == .canceled {
            forcedStatus = nil
        } else if database.databaseScope == .shared || participation.hasAcceptedNonOwner {
            forcedStatus = .accepted
        } else {
            forcedStatus = nil
        }

        return try Self.snapshot(
            from: record,
            shareLocator: record.share.map { CompanionRecordLocator(recordID: $0.recordID) },
            forcedStatus: forcedStatus,
            participantDisplayNames: participation.participantDisplayNames
        )
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        try await ensureAccountAvailable()
        let query = CKQuery(
            recordType: CompanionSessionRecord.recordType,
            predicate: NSPredicate(value: true)
        )
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch {
            throw Self.mapError(error)
        }

        var sessionsByLocator: [CompanionRecordLocator: CompanionSessionSnapshot] = [:]
        var firstZoneError: CompanionSharingError?
        for zone in zones {
            do {
                var cursor: CKQueryOperation.Cursor?
                repeat {
                    let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                    if let cursor {
                        page = try await sharedDB.records(
                            continuingMatchFrom: cursor,
                            desiredKeys: nil,
                            resultsLimit: 50
                        )
                    } else {
                        page = try await sharedDB.records(
                            matching: query,
                            inZoneWith: zone.zoneID,
                            desiredKeys: nil,
                            resultsLimit: 50
                        )
                    }
                    for (_, result) in page.matchResults {
                        guard case .success(let record) = result else { continue }
                        let participation = (try? await shareParticipationState(for: record, in: sharedDB)) ?? .empty
                        let rootStatus = (record[CompanionSessionRecord.status] as? String)
                            .flatMap(CompanionCloudStatus.init(rawValue:))
                        let forcedStatus: CompanionCloudStatus? = rootStatus == .canceled ? nil : .accepted
                        guard let snapshot = try? Self.snapshot(
                            from: record,
                            shareLocator: record.share.map { CompanionRecordLocator(recordID: $0.recordID) },
                            forcedStatus: forcedStatus,
                            participantDisplayNames: participation.participantDisplayNames
                        ) else { continue }
                        if snapshot.status == .accepted {
                            sessionsByLocator[snapshot.sessionLocator] = snapshot
                        }
                    }
                    cursor = page.queryCursor
                } while cursor != nil
            } catch {
                firstZoneError = firstZoneError ?? Self.mapError(error)
            }
        }

        if !sessionsByLocator.isEmpty || firstZoneError == nil {
            return Array(sessionsByLocator.values)
        }
        throw firstZoneError!
    }

    func reconcileOwnerMembership(
        shareLocator: CompanionRecordLocator
    ) async throws -> CompanionMembershipState {
        try await ensureAccountAvailable()

        do {
            guard let share = try await privateDB.record(for: shareLocator.recordID) as? CKShare else {
                throw CompanionSharingError.sessionNotFound
            }

            let statuses: [CompanionShareMemberStatus] = share.participants.compactMap { participant in
                guard participant.role != .owner else { return nil }
                switch participant.acceptanceStatus {
                case .accepted: return .accepted
                case .pending: return .pending
                case .removed: return .removed
                default: return .unknown
                }
            }
            return CompanionMembershipPolicy.evaluate(nonOwnerStatuses: statuses)
        } catch {
            throw Self.mapError(error)
        }
    }

    private func cancelAsOwner(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?
    ) async throws -> CompanionSessionSnapshot {
        let (record, database) = try await fetchSessionRecord(locator: sessionLocator)

        record[CompanionSessionRecord.status] = CompanionCloudStatus.canceled.rawValue as CKRecordValue
        record[CompanionSessionRecord.canceledAt] = Date() as CKRecordValue
        record[CompanionSessionRecord.acceptedAt] = nil
        let saved = try await modifyRecords(in: database, saving: [record]).first ?? record

        var retainedShareLocator: CompanionRecordLocator? = nil
        if let shareLocator {
            do {
                let shareRecord = try await privateDB.record(for: shareLocator.recordID)
                if let share = shareRecord as? CKShare {
                    _ = try await modifyRecords(
                        in: privateDB,
                        saving: [],
                        deleting: [share.recordID]
                    )
                }
            } catch {
                let mapped = Self.mapError(error)
                if mapped == .sessionNotFound {
                    retainedShareLocator = nil
                } else {
                    retainedShareLocator = shareLocator
                    throw mapped
                }
            }
        }

        return try Self.snapshot(from: saved, shareLocator: retainedShareLocator)
    }

    private func cancelAsParticipant(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?
    ) async throws -> CompanionSessionSnapshot {
        var currentSnapshot: CompanionSessionSnapshot?
        var fetchError: CompanionSharingError?
        do {
            let (record, database) = try await fetchSessionRecord(locator: sessionLocator)
            let names = try await participantNames(for: record, in: database)
            currentSnapshot = try Self.snapshot(
                from: record,
                shareLocator: shareLocator,
                forcedStatus: .accepted,
                participantDisplayNames: names
            )
        } catch {
            fetchError = Self.mapError(error)
        }

        var shareLeaveSucceeded = false
        if let shareLocator {
            do {
                let shareRecord = try await sharedDB.record(for: shareLocator.recordID)
                if shareRecord is CKShare {
                    _ = try await modifyRecords(
                        in: sharedDB,
                        saving: [],
                        deleting: [shareLocator.recordID]
                    )
                }
                shareLeaveSucceeded = true
            } catch {
                let mapped = Self.mapError(error)
                if mapped == .sessionNotFound {
                    shareLeaveSucceeded = true
                } else {
                    throw mapped
                }
            }
        } else {
            shareLeaveSucceeded = true
        }

        if let currentSnapshot {
            return currentSnapshot
        }

        if !shareLeaveSucceeded, let fetchError {
            throw fetchError
        }

        return CompanionSessionSnapshot(
            sessionLocator: sessionLocator,
            shareLocator: nil,
            show: CompanionShowSnapshot(
                showID: "",
                showName: "",
                showDate: Date(),
                showStartTime: Date(),
                showLocation: nil
            ),
            ownerDisplayName: nil,
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: .canceled,
            createdAt: Date(),
            acceptedAt: nil,
            canceledAt: Date()
        )
    }

    private func participantNames(for record: CKRecord, in database: CKDatabase) async throws -> [String] {
        try await shareParticipationState(for: record, in: database).participantDisplayNames
    }

    private func shareParticipationState(
        for record: CKRecord,
        in database: CKDatabase
    ) async throws -> CompanionShareParticipationState {
        guard let shareRef = record.share else { return .empty }
        do {
            guard let share = try await database.record(for: shareRef.recordID) as? CKShare else {
                return .empty
            }
            let hasAcceptedNonOwner = share.participants.contains { participant in
                participant.role != .owner && participant.acceptanceStatus == .accepted
            }
            return CompanionShareParticipationState(
                participantDisplayNames: Self.participantNames(from: share),
                hasAcceptedNonOwner: hasAcceptedNonOwner
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    private func fetchSessionRecord(
        locator: CompanionRecordLocator
    ) async throws -> (CKRecord, CKDatabase) {
        let database: CKDatabase =
            locator.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        do {
            let record = try await database.record(for: locator.recordID)
            return (record, database)
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func displayName(for identity: CKUserIdentity) -> String? {
        guard let components = identity.nameComponents else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}
