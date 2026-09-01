import CloudKit
import Foundation

extension CloudKitCompanionSharingService {
    // MARK: Helpers

    func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        CompanionDebugLog.write("iCloud account status: \(status.rawValue)")
        guard status == .available else {
            throw CompanionSharingError.iCloudAccountUnavailable
        }
    }

    func modifyRecords(
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

    static func mapError(
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
