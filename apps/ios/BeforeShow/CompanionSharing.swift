import CloudKit
import Foundation

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

struct CompanionShowSnapshot: Equatable, Sendable {
    var showID: String
    var showName: String
    var showDate: Date
    var showLocation: String?
}

struct CompanionSessionSnapshot: Equatable, Sendable {
    var recordName: String
    var shareRecordName: String?
    var show: CompanionShowSnapshot
    var ownerDisplayName: String?
    var participantDisplayName: String?
    var status: CompanionCloudStatus
    var createdAt: Date
    var acceptedAt: Date?
    var canceledAt: Date?

    /// Name the local device should show for the other person.
    func companionDisplayName(isOwner: Bool) -> String? {
        let raw = isOwner ? participantDisplayName : ownerDisplayName
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
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
}

// MARK: - Service protocol

protocol CompanionSharingService: Sendable {
    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare

    func loadShareSystemFields(shareRecordName: String) async throws -> Data

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot

    func cancelSession(recordName: String) async throws -> CompanionSessionSnapshot

    func fetchSession(recordName: String) async throws -> CompanionSessionSnapshot
}

// MARK: - CloudKit field keys

enum CompanionSessionRecord {
    static let recordType = "CompanionSession"
    static let showID = "showID"
    static let showName = "showName"
    static let showDate = "showDate"
    static let showLocation = "showLocation"
    static let ownerDisplayName = "ownerDisplayName"
    static let participantDisplayName = "participantDisplayName"
    static let status = "status"
    static let createdAt = "createdAt"
    static let acceptedAt = "acceptedAt"
    static let canceledAt = "canceledAt"
}

// MARK: - CloudKit implementation

struct CloudKitCompanionSharingService: CompanionSharingService {
    let container: CKContainer

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

        let session = CKRecord(recordType: CompanionSessionRecord.recordType)
        let now = Date()
        session[CompanionSessionRecord.showID] = show.showID as CKRecordValue
        session[CompanionSessionRecord.showName] = show.showName as CKRecordValue
        session[CompanionSessionRecord.showDate] = show.showDate as CKRecordValue
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
        share[CKShare.SystemFieldKey.title] = "一起去 \(show.showName)" as CKRecordValue
        share.publicPermission = .none

        let saved = try await modifyRecords(in: privateDB, saving: [session, share])
        guard
            let savedSession = saved.first(where: { $0.recordID.recordName == session.recordID.recordName }),
            let savedShare = saved.compactMap({ $0 as? CKShare }).first
                ?? saved.first(where: { $0.recordID.recordName == share.recordID.recordName }) as? CKShare
        else {
            throw CompanionSharingError.sharePreparationFailed
        }

        let snapshot = try Self.snapshot(from: savedSession, shareRecordName: savedShare.recordID.recordName)
        let fields = try NSKeyedArchiver.archivedData(
            withRootObject: savedShare,
            requiringSecureCoding: true
        )
        return CompanionPreparedShare(session: snapshot, shareSystemFields: fields)
    }

    func loadShareSystemFields(shareRecordName: String) async throws -> Data {
        try await ensureAccountAvailable()
        let recordID = CKRecord.ID(recordName: shareRecordName)
        let record = try await privateDB.record(for: recordID)
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

        do {
            try await container.accept(metadata)
        } catch {
            throw CompanionSharingError.acceptFailed
        }

        let rootID = metadata.hierarchicalRootRecordID ?? metadata.rootRecordID

        // Shared records live in the shared database zone of the owner.
        let record: CKRecord
        do {
            record = try await sharedDB.record(for: rootID)
        } catch {
            // Fallback: some accept paths surface the record via private DB after accept.
            do {
                record = try await privateDB.record(for: rootID)
            } catch {
                throw CompanionSharingError.sessionNotFound
            }
        }

        if let participantDisplayName, !participantDisplayName.isEmpty {
            record[CompanionSessionRecord.participantDisplayName] = participantDisplayName as CKRecordValue
        }
        record[CompanionSessionRecord.status] = CompanionCloudStatus.accepted.rawValue as CKRecordValue
        record[CompanionSessionRecord.acceptedAt] = Date() as CKRecordValue

        let saved: CKRecord
        do {
            let results = try await modifyRecords(in: sharedDB, saving: [record])
            saved = results.first ?? record
        } catch {
            // Participant may only have read permission; still treat accept as confirmed locally.
            // Owner will see participant join via share participants even if status write fails.
            return try Self.snapshot(
                from: record,
                shareRecordName: metadata.share.recordID.recordName,
                forcedStatus: .accepted
            )
        }

        return try Self.snapshot(
            from: saved,
            shareRecordName: metadata.share.recordID.recordName
        )
    }

    func cancelSession(recordName: String) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()

        let recordID = CKRecord.ID(recordName: recordName)
        let (record, database) = try await fetchSessionRecord(recordID: recordID)
        record[CompanionSessionRecord.status] = CompanionCloudStatus.canceled.rawValue as CKRecordValue
        record[CompanionSessionRecord.canceledAt] = Date() as CKRecordValue
        let saved = try await modifyRecords(in: database, saving: [record]).first ?? record
        return try Self.snapshot(from: saved, shareRecordName: nil)
    }

    func fetchSession(recordName: String) async throws -> CompanionSessionSnapshot {
        try await ensureAccountAvailable()
        let recordID = CKRecord.ID(recordName: recordName)
        let (record, _) = try await fetchSessionRecord(recordID: recordID)
        return try Self.snapshot(from: record, shareRecordName: nil)
    }

    // MARK: Helpers

    private func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CompanionSharingError.iCloudAccountUnavailable
        }
    }

    private func fetchSessionRecord(
        recordID: CKRecord.ID
    ) async throws -> (CKRecord, CKDatabase) {
        do {
            let record = try await privateDB.record(for: recordID)
            return (record, privateDB)
        } catch {
            do {
                let record = try await sharedDB.record(for: recordID)
                return (record, sharedDB)
            } catch {
                throw CompanionSharingError.sessionNotFound
            }
        }
    }

    private func modifyRecords(
        in database: CKDatabase,
        saving records: [CKRecord]
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
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

    private static func mapError(_ error: Error) -> CompanionSharingError {
        let ck = error as? CKError
        switch ck?.code {
        case .notAuthenticated, .managedAccountRestricted:
            return .iCloudAccountUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return .networkFailure
        case .permissionFailure:
            return .permissionDenied
        case .unknownItem:
            return .sessionNotFound
        default:
            return .sharePreparationFailed
        }
    }

    static func snapshot(
        from record: CKRecord,
        shareRecordName: String?,
        forcedStatus: CompanionCloudStatus? = nil
    ) throws -> CompanionSessionSnapshot {
        guard
            let showID = record[CompanionSessionRecord.showID] as? String,
            let showName = record[CompanionSessionRecord.showName] as? String
        else {
            throw CompanionSharingError.invalidPayload
        }

        let showDate = (record[CompanionSessionRecord.showDate] as? Date) ?? Date()
        let statusRaw = record[CompanionSessionRecord.status] as? String
        let status = forcedStatus
            ?? statusRaw.flatMap(CompanionCloudStatus.init(rawValue:))
            ?? .pending

        return CompanionSessionSnapshot(
            recordName: record.recordID.recordName,
            shareRecordName: shareRecordName,
            show: CompanionShowSnapshot(
                showID: showID,
                showName: showName,
                showDate: showDate,
                showLocation: record[CompanionSessionRecord.showLocation] as? String
            ),
            ownerDisplayName: record[CompanionSessionRecord.ownerDisplayName] as? String,
            participantDisplayName: record[CompanionSessionRecord.participantDisplayName] as? String,
            status: status,
            createdAt: (record[CompanionSessionRecord.createdAt] as? Date) ?? Date(),
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
        companionCloudRecordName = snapshot.recordName
        if let shareName = snapshot.shareRecordName {
            companionShareRecordName = shareName
        }
        companionIsOwner = isOwner

        let cloudName = snapshot.companionDisplayName(isOwner: isOwner)
        let fallback = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String?
        if let cloudName {
            resolvedName = cloudName
        } else if let fallback, !fallback.isEmpty {
            resolvedName = fallback
        } else {
            resolvedName = companionName
        }

        applyCompanionState(status: snapshot.status.localStatus, name: resolvedName)
    }

    func clearCompanionCloudLinkage() {
        companionCloudRecordName = nil
        companionShareRecordName = nil
        companionIsOwner = nil
    }
}
