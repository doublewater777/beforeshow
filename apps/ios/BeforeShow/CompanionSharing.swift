import CloudKit
import Foundation
import os

// MARK: - Domain

/// CloudKit-side companion session status (maps to local `ShowCompanionStatus`).
enum CompanionCloudStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case pending
    case accepted
    case canceled

    var localStatus: ShowCompanionStatus {
        switch self {
        case .pending: return .pending
        case .accepted: return .confirmed
        case .canceled: return .canceled
        }
    }
}

/// Full CloudKit record identity (name + zone + owner).
/// Sharing requires a custom private zone; default-zone records cannot be shared.
struct CompanionRecordLocator: Equatable, Sendable, Codable, Hashable {
    static let companionZoneName = "CompanionSessions"

    var recordName: String
    var zoneName: String
    var ownerName: String

    init(
        recordName: String,
        zoneName: String = CompanionRecordLocator.companionZoneName,
        ownerName: String = CKCurrentUserDefaultName
    ) {
        self.recordName = recordName
        self.zoneName = zoneName
        self.ownerName = ownerName
    }

    init(recordID: CKRecord.ID) {
        self.recordName = recordID.recordName
        self.zoneName = recordID.zoneID.zoneName
        self.ownerName = recordID.zoneID.ownerName
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    var recordID: CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Shared-database zone IDs use the share owner's identity, not the current user token.
    func sharedDatabaseLocator(ownerName sharedOwnerName: String) -> CompanionRecordLocator {
        CompanionRecordLocator(
            recordName: recordName,
            zoneName: zoneName,
            ownerName: sharedOwnerName
        )
    }
}

struct CompanionShowSnapshot: Equatable, Sendable {
    var showID: String
    var showName: String
    var showDate: Date
    var showStartTime: Date
    var showLocation: String?
}

struct CompanionSessionSnapshot: Equatable, Sendable {
    var sessionLocator: CompanionRecordLocator
    var shareLocator: CompanionRecordLocator?
    var show: CompanionShowSnapshot
    var ownerDisplayName: String?
    var participantDisplayName: String?
    var participantDisplayNames: [String]
    var status: CompanionCloudStatus
    var createdAt: Date
    var acceptedAt: Date?
    var canceledAt: Date?

    /// Convenience for tests / call sites that only need the record name.
    var recordName: String { sessionLocator.recordName }
    var shareRecordName: String? { shareLocator?.recordName }

    /// Names this device should show for the other people in the group.
    func companionDisplayNames(isOwner: Bool) -> [String] {
        let listed = CompanionNameList.normalized(participantDisplayNames)
        if isOwner {
            if !listed.isEmpty { return listed }
            return CompanionNameList.normalized([participantDisplayName].compactMap { $0 })
        }
        var names = CompanionNameList.normalized([ownerDisplayName].compactMap { $0 })
        names.append(contentsOf: listed)
        if names.isEmpty {
            names = CompanionNameList.normalized([participantDisplayName].compactMap { $0 })
        }
        return CompanionNameList.normalized(names)
    }

    /// Joined display name for the other people in the group.
    func companionDisplayName(isOwner: Bool) -> String? {
        CompanionNameList.joined(companionDisplayNames(isOwner: isOwner))
    }
}

struct CompanionPreparedShare: Equatable, Sendable {
    var session: CompanionSessionSnapshot
    /// Opaque handle for presenting system CloudKit sharing UI.
    var shareSystemFields: Data
}

enum CompanionSharingError: Error, Equatable, Sendable {
    case iCloudAccountUnavailable
    case networkFailure
    case sharePreparationFailed
    case acceptFailed
    case sessionNotFound
    case invalidPayload
    case permissionDenied
    case conflict
    /// Share was accepted but session status could not be synchronized yet.
    case statusSyncPending
}

enum CompanionMembershipState: Equatable, Sendable {
    case healthy
    case removed
    case warning(String)

    var warning: String? {
        if case .warning(let message) = self { return message }
        return nil
    }
}

enum CompanionShareMemberStatus: Equatable, Sendable {
    case accepted
    case pending
    case removed
    case unknown
}

/// Owner-side share membership without mutating CloudKit.
/// Multiple accepted members are a valid group; outstanding invites are not warnings.
enum CompanionMembershipPolicy {
    static func evaluate(
        nonOwnerStatuses: [CompanionShareMemberStatus]
    ) -> CompanionMembershipState {
        let accepted = nonOwnerStatuses.filter { $0 == .accepted }.count
        let pending = nonOwnerStatuses.filter { $0 == .pending }.count
        let unknown = nonOwnerStatuses.filter { $0 == .unknown }.count

        if accepted == 0, unknown == 0 {
            return .removed
        }
        if unknown > 0 {
            return .warning("同行成员状态暂时无法确认，请稍后重试")
        }
        return .healthy
    }
}

enum CompanionNameList {
    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    static func joined(_ names: [String]) -> String? {
        let cleaned = normalized(names)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: "、")
    }

    static func isSameGroup(_ lhs: [String], _ rhs: [String]) -> Bool {
        Set(normalized(lhs)) == Set(normalized(rhs))
    }
}

// MARK: - Service protocol

protocol CompanionSharingService: Sendable {
    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare

    func loadShareSystemFields(shareLocator: CompanionRecordLocator) async throws -> Data

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot

    func cancelSession(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?,
        isOwner: Bool
    ) async throws -> CompanionSessionSnapshot

    func fetchSession(sessionLocator: CompanionRecordLocator) async throws -> CompanionSessionSnapshot

    /// Discover already-accepted shared companion sessions for startup recovery.
    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot]

    /// Reconcile the owner-side share. Multiple accepted members are a valid group.
    func reconcileOwnerMembership(
        shareLocator: CompanionRecordLocator
    ) async throws -> CompanionMembershipState
}

// MARK: - CloudKit field keys

enum CompanionSessionRecord {
    static let recordType = "CompanionSession"
    static let showID = "showID"
    static let showName = "showName"
    static let showDate = "showDate"
    static let showStartTime = "showStartTime"
    static let showLocation = "showLocation"
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

struct CloudKitCompanionSharingService: CompanionSharingService {
    let container: CKContainer
    private static let log = Logger(subsystem: "com.doublewaterapps.beforeshow", category: "companion")

    static let defaultContainerIdentifier = "iCloud.com.doublewaterapps.beforeshow"

    static func live() -> CloudKitCompanionSharingService {
        CloudKitCompanionSharingService(
            container: CKContainer(identifier: defaultContainerIdentifier)
        )
    }

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare {
        try await ensureAccountAvailable()
        await debugProbeDefaultZone()
        let zone = try await ensureCompanionZone()
        CompanionDebugLog.write("Preparing companion invite in zone \(zone.zoneID.zoneName)")

        let sessionID = CKRecord.ID(
            recordName: "session-\(UUID().uuidString)",
            zoneID: zone.zoneID
        )
        let session = CKRecord(recordType: CompanionSessionRecord.recordType, recordID: sessionID)
        let now = Date()
        session[CompanionSessionRecord.showID] = show.showID as CKRecordValue
        session[CompanionSessionRecord.showName] = show.showName as CKRecordValue
        session[CompanionSessionRecord.showDate] = show.showDate as CKRecordValue
        session[CompanionSessionRecord.showStartTime] = show.showStartTime as CKRecordValue
        if let location = show.showLocation, !location.isEmpty {
            session[CompanionSessionRecord.showLocation] = location as CKRecordValue
        }
        if let ownerDisplayName, !ownerDisplayName.isEmpty {
            session[CompanionSessionRecord.ownerDisplayName] = ownerDisplayName as CKRecordValue
        }
        if let preferredParticipantName, !preferredParticipantName.isEmpty {
            session[CompanionSessionRecord.participantDisplayName] = preferredParticipantName as CKRecordValue
        }
        session[CompanionSessionRecord.status] = CompanionCloudStatus.pending.rawValue as CKRecordValue
        session[CompanionSessionRecord.createdAt] = now as CKRecordValue

        let share = CKShare(rootRecord: session)
        share[CKShare.SystemFieldKey.title] = BSLocalization.format("一起去 %@", show.showName) as CKRecordValue
        share.publicPermission = .none

        let saved: [CKRecord]
        do {
            saved = try await modifyRecords(in: privateDB, saving: [session, share])
        } catch {
            CompanionDebugLog.write("Saving companion share failed: \(error)")
            throw error
        }
        guard
            let savedSession = saved.first(where: { $0.recordID.recordName == session.recordID.recordName }),
            let savedShare = saved.compactMap({ $0 as? CKShare }).first
                ?? saved.first(where: { $0.recordID.recordName == share.recordID.recordName }) as? CKShare
        else {
            CompanionDebugLog.write("Companion save succeeded without a CKShare payload")
            throw CompanionSharingError.sharePreparationFailed
        }

        let snapshot = try Self.snapshot(
            from: savedSession,
            shareLocator: CompanionRecordLocator(recordID: savedShare.recordID)
        )
        let fields = try NSKeyedArchiver.archivedData(
            withRootObject: savedShare,
            requiringSecureCoding: true
        )
        return CompanionPreparedShare(session: snapshot, shareSystemFields: fields)
    }

    func loadShareSystemFields(shareLocator: CompanionRecordLocator) async throws -> Data {
        try await ensureAccountAvailable()
        let record = try await privateDB.record(for: shareLocator.recordID)
        guard let share = record as? CKShare else {
            throw CompanionSharingError.sessionNotFound
        }
        return try NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
    }

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
        let names = await participantNames(for: record, in: database)
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

    // MARK: Helpers

    private func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        CompanionDebugLog.write("iCloud account status: \(status.rawValue)")
        guard status == .available else {
            throw CompanionSharingError.iCloudAccountUnavailable
        }
    }

    private func debugProbeDefaultZone() async {
        do {
            let record = CKRecord(recordType: "CompanionDebugProbe")
            record["ok"] = "1" as CKRecordValue
            _ = try await privateDB.save(record)
            CompanionDebugLog.write("Default-zone probe save succeeded")
        } catch {
            let ns = error as NSError
            CompanionDebugLog.write("Default-zone probe save failed: \(error) userInfo=\(ns.userInfo)")
        }
    }

    private func ensureCompanionZone() async throws -> CKRecordZone {
        let zoneID = CKRecordZone.ID(
            zoneName: CompanionRecordLocator.companionZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            let result = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
            if let saved = result.saveResults[zoneID] {
                switch saved {
                case .success(let zone):
                    return zone
                case .failure(let error):
                    CompanionDebugLog.write(
                        "Creating companion zone returned: \(error) userInfo=\((error as NSError).userInfo)"
                    )
                    // Zone already exists is fine — re-fetch.
                    if (error as? CKError)?.code == .serverRecordChanged
                        || (error as? CKError)?.code == .zoneNotFound
                        || (error as? CKError)?.code == .partialFailure {
                        break
                    }
                    throw error
                }
            }
        } catch {
            CompanionDebugLog.write("Creating companion zone failed: \(error)")
        }

        do {
            let zones = try await privateDB.recordZones(for: [zoneID])
            if let existing = try zones[zoneID]?.get() {
                return existing
            }
        } catch {
            CompanionDebugLog.write("Fetching companion zone failed: \(error)")
            throw Self.mapError(error)
        }

        CompanionDebugLog.write("Companion zone is missing after create and fetch")
        throw CompanionSharingError.sharePreparationFailed
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
            let names = await participantNames(for: record, in: database)
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

    private func participantNames(for record: CKRecord, in database: CKDatabase) async -> [String] {
        guard let shareRef = record.share else { return [] }
        do {
            guard let share = try await database.record(for: shareRef.recordID) as? CKShare else {
                return []
            }
            return Self.participantNames(from: share)
        } catch {
            return []
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

    private func modifyRecords(
        in database: CKDatabase,
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID] = []
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: records.isEmpty ? nil : records,
                recordIDsToDelete: recordIDs.isEmpty ? nil : recordIDs
            )
            // Enforce change-tag conflicts so concurrent accept/cancel cannot last-writer-win.
            operation.savePolicy = .ifServerRecordUnchanged
            operation.qualityOfService = .userInitiated

            var saved: [CKRecord] = []
            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result {
                    saved.append(record)
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: saved)
                case .failure(let error):
                    continuation.resume(throwing: Self.mapError(error))
                }
            }
            database.add(operation)
        }
    }

    private static func mapError(
        _ error: Error,
        fallback: CompanionSharingError = .sharePreparationFailed
    ) -> CompanionSharingError {
        if let sharing = error as? CompanionSharingError {
            return sharing
        }
        let ck = error as? CKError
        switch ck?.code {
        case .notAuthenticated, .managedAccountRestricted:
            return .iCloudAccountUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return .networkFailure
        case .permissionFailure:
            return .permissionDenied
        case .unknownItem, .zoneNotFound:
            // Missing zone/record both mean the linked hierarchy is gone from this DB view.
            return .sessionNotFound
        case .serverRecordChanged, .batchRequestFailed:
            return .conflict
        case .serverRejectedRequest:
            return .sharePreparationFailed
        default:
            // partialFailure may wrap unknownItem or network errors.
            if let partial = ck?.partialErrorsByItemID?.values {
                let mapped = partial.map { mapError($0, fallback: fallback) }
                if mapped.contains(.networkFailure) { return .networkFailure }
                if mapped.contains(.permissionDenied) { return .permissionDenied }
                if mapped.contains(.conflict) { return .conflict }
                if mapped.allSatisfy({ $0 == .sessionNotFound }) { return .sessionNotFound }
            }
            return fallback
        }
    }

    static func participantNames(from share: CKShare) -> [String] {
        let currentID = share.currentUserParticipant?.participantID
        return CompanionNameList.normalized(share.participants.compactMap { participant in
            guard participant.role != .owner else { return nil }
            guard participant.acceptanceStatus == .accepted else { return nil }
            if let currentID, participant.participantID == currentID { return nil }
            return displayName(for: participant)
        })
    }

    static func displayName(for participant: CKShare.Participant) -> String? {
        guard let components = participant.userIdentity.nameComponents else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    static func snapshot(
        from record: CKRecord,
        shareLocator: CompanionRecordLocator?,
        forcedStatus: CompanionCloudStatus? = nil,
        participantDisplayNames: [String] = []
    ) throws -> CompanionSessionSnapshot {
        guard
            let showID = record[CompanionSessionRecord.showID] as? String,
            let showName = record[CompanionSessionRecord.showName] as? String,
            let showDate = record[CompanionSessionRecord.showDate] as? Date,
            let createdAt = record[CompanionSessionRecord.createdAt] as? Date
        else {
            throw CompanionSharingError.invalidPayload
        }
        let showStartTime = (record[CompanionSessionRecord.showStartTime] as? Date) ?? showDate

        let status: CompanionCloudStatus
        if let forcedStatus {
            status = forcedStatus
        } else if let statusRaw = record[CompanionSessionRecord.status] as? String,
                  let parsed = CompanionCloudStatus(rawValue: statusRaw) {
            status = parsed
        } else {
            throw CompanionSharingError.invalidPayload
        }

        return CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(recordID: record.recordID),
            shareLocator: shareLocator,
            show: CompanionShowSnapshot(
                showID: showID,
                showName: showName,
                showDate: showDate,
                showStartTime: showStartTime,
                showLocation: record[CompanionSessionRecord.showLocation] as? String
            ),
            ownerDisplayName: record[CompanionSessionRecord.ownerDisplayName] as? String,
            participantDisplayName: record[CompanionSessionRecord.participantDisplayName] as? String,
            participantDisplayNames: CompanionNameList.normalized(participantDisplayNames),
            status: status,
            createdAt: createdAt,
            acceptedAt: record[CompanionSessionRecord.acceptedAt] as? Date,
            canceledAt: record[CompanionSessionRecord.canceledAt] as? Date
        )
    }

    static func unarchiveShare(from data: Data) throws -> CKShare {
        guard let share = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKShare.self,
            from: data
        ) else {
            throw CompanionSharingError.invalidPayload
        }
        return share
    }
}

// MARK: - Local show mapping

extension CompanionShowSnapshot {
    init(show: Show) {
        let locationParts = [show.venueName, show.city]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let trimmed, !trimmed.isEmpty else { return nil }
                return trimmed
            }
        self.init(
            showID: show.id.uuidString,
            showName: show.name,
            showDate: show.effectiveDate,
            showStartTime: show.startTime,
            showLocation: locationParts.isEmpty ? nil : locationParts.joined(separator: " · ")
        )
    }
}

extension Show {
    /// Apply a CloudKit session onto local cache fields.
    func applyCompanionSession(
        _ snapshot: CompanionSessionSnapshot,
        isOwner: Bool,
        preferredName: String? = nil
    ) {
        companionCloudRecordName = snapshot.sessionLocator.recordName
        companionCloudZoneName = snapshot.sessionLocator.zoneName
        companionCloudOwnerName = snapshot.sessionLocator.ownerName
        if let shareLocator = snapshot.shareLocator {
            companionShareRecordName = shareLocator.recordName
            companionShareZoneName = shareLocator.zoneName
            companionShareOwnerName = shareLocator.ownerName
        }
        companionIsOwner = isOwner

        let cloudNames = snapshot.companionDisplayNames(isOwner: isOwner)
        let fallback = CompanionNameList.normalized([preferredName].compactMap { $0 })
        let resolvedNames: [String]
        if !cloudNames.isEmpty {
            resolvedNames = cloudNames
        } else if !fallback.isEmpty {
            resolvedNames = fallback
        } else {
            resolvedNames = companionNames
        }

        applyCompanionState(status: snapshot.status.localStatus, names: resolvedNames)
    }

    func clearCompanionCloudLinkage() {
        companionCloudRecordName = nil
        companionCloudZoneName = nil
        companionCloudOwnerName = nil
        companionShareRecordName = nil
        companionShareZoneName = nil
        companionShareOwnerName = nil
        companionIsOwner = nil
    }

    var companionSessionLocator: CompanionRecordLocator? {
        guard let recordName = companionCloudRecordName else { return nil }
        return CompanionRecordLocator(
            recordName: recordName,
            zoneName: companionCloudZoneName ?? CompanionRecordLocator.companionZoneName,
            ownerName: companionCloudOwnerName ?? CKCurrentUserDefaultName
        )
    }

    var companionShareLocator: CompanionRecordLocator? {
        guard let recordName = companionShareRecordName else { return nil }
        return CompanionRecordLocator(
            recordName: recordName,
            zoneName: companionShareZoneName
                ?? companionCloudZoneName
                ?? CompanionRecordLocator.companionZoneName,
            ownerName: companionShareOwnerName
                ?? companionCloudOwnerName
                ?? CKCurrentUserDefaultName
        )
    }
}
