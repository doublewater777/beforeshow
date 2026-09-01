import CloudKit
import Foundation

extension CloudKitCompanionSharingService {
    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()

        let shareLocator = CompanionRecordLocator(recordID: metadata.share.recordID)
        let acceptedShare: CKShare
        do {
            acceptedShare = try await container.accept(metadata)
        } catch {
            // Accepting an already-accepted share is fine; map other failures precisely.
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
                // The share was already accepted, but a transient refetch failure must remain
                // retryable so the durable inbox is not discarded.
                throw Self.mapError(error, fallback: .statusSyncPending)
            }
        }

        guard let rootID = metadata.hierarchicalRootRecordID else {
            throw CompanionSharingError.invalidPayload
        }

        let record: CKRecord
        do {
            record = try await sharedDB.record(for: rootID)
        } catch {
            throw Self.mapError(error)
        }

        // Validate root payload BEFORE mutating status. If invalid after container.accept,
        // attempt compensating leave so residual access is not retained silently.
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

        // Reject resurrecting a canceled invitation.
        if let statusRaw = record[CompanionSessionRecord.status] as? String,
           statusRaw == CompanionCloudStatus.canceled.rawValue {
            try await leaveShareOrThrowCleanupPending()
            throw CompanionSharingError.permissionDenied
        }

        // Validate required fields before writing acceptance.
        do {
            _ = try Self.snapshot(from: record, shareLocator: shareLocator)
        } catch {
            // Successful compensating leave makes this terminal for the accept job.
            try await leaveShareOrThrowCleanupPending()
            throw CompanionSharingError.invalidPayload
        }

        let harvestedNames = Self.participantNames(from: acceptedShare)

        // A root already accepted by this participant — or by earlier members —
        // is idempotent. Additional members join the same accepted session.
        if let existingStatus = record[CompanionSessionRecord.status] as? String,
           existingStatus == CompanionCloudStatus.accepted.rawValue {
            return try Self.snapshot(
                from: record,
                shareLocator: shareLocator,
                participantDisplayNames: harvestedNames
            )
        }

        let existingParticipantName = (record[CompanionSessionRecord.participantDisplayName] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let participantDisplayName, !participantDisplayName.isEmpty,
           existingParticipantName == nil || existingParticipantName?.isEmpty == true {
            record[CompanionSessionRecord.participantDisplayName] = participantDisplayName as CKRecordValue
        }
        record[CompanionSessionRecord.status] = CompanionCloudStatus.accepted.rawValue as CKRecordValue
        record[CompanionSessionRecord.acceptedAt] = Date() as CKRecordValue
        // Clear a previous cancel marker if present so timestamps stay consistent.
        record[CompanionSessionRecord.canceledAt] = nil

        do {
            let results = try await modifyRecords(in: sharedDB, saving: [record])
            let saved = results.first ?? record
            return try Self.snapshot(
                from: saved,
                shareLocator: shareLocator,
                participantDisplayNames: harvestedNames
            )
        } catch {
            // Share is accepted in CloudKit, but session status is not durable yet.
            throw CompanionSharingError.statusSyncPending
        }
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
        let names = try await participantNames(for: record, in: database)
        return try Self.snapshot(
            from: record,
            shareLocator: record.share.map { CompanionRecordLocator(recordID: $0.recordID) },
            participantDisplayNames: names
        )
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        try await ensureAccountAvailable()
        // Query all CompanionSession records visible in the shared database.
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
                        guard let snapshot = try? Self.snapshot(
                            from: record,
                            shareLocator: record.share.map { CompanionRecordLocator(recordID: $0.recordID) }
                        ) else { continue }
                        if snapshot.status == .accepted || snapshot.status == .pending {
                            sessionsByLocator[snapshot.sessionLocator] = snapshot
                        }
                    }
                    cursor = page.queryCursor
                } while cursor != nil
            } catch {
                // A stale or unavailable shared zone must not hide sessions from other zones.
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

        // Mark canceled first so late acceptors can reject and participants can observe cancel
        // before access is revoked.
        record[CompanionSessionRecord.status] = CompanionCloudStatus.canceled.rawValue as CKRecordValue
        record[CompanionSessionRecord.canceledAt] = Date() as CKRecordValue
        record[CompanionSessionRecord.acceptedAt] = nil
        let saved = try await modifyRecords(in: database, saving: [record]).first ?? record

        // Revoke the share so old invitation URLs stop granting access.
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
                    // Keep share locator so the coordinator can retry revocation.
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
        // Leave the share only. Writing session status=canceled would dissolve the
        // remaining group. The leaving device still marks local companion canceled.
        var currentSnapshot: CompanionSessionSnapshot?
        var fetchError: CompanionSharingError?
        do {
            let (record, database) = try await fetchSessionRecord(locator: sessionLocator)
            let names = try await participantNames(for: record, in: database)
            currentSnapshot = try Self.snapshot(
                from: record,
                shareLocator: shareLocator,
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
                // Already gone is success; anything else means access may still exist.
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
        guard let shareRef = record.share else { return [] }
        do {
            guard let share = try await database.record(for: shareRef.recordID) as? CKShare else {
                return []
            }
            return Self.participantNames(from: share)
        } catch {
            throw Self.mapError(error)
        }
    }

    private func fetchSessionRecord(
        locator: CompanionRecordLocator
    ) async throws -> (CKRecord, CKDatabase) {
        // Deterministic database selection: current-user zones live in private DB;
        // owner-qualified zones (participant view of a shared hierarchy) live in shared DB.
        let database: CKDatabase =
            locator.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        do {
            let record = try await database.record(for: locator.recordID)
            return (record, database)
        } catch {
            throw Self.mapError(error)
        }
    }
}
