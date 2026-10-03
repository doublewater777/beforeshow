import CloudKit
import Foundation

extension CloudKitCompanionSharingService {
    func ensureAccountAvailable() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            CompanionCloudDiagnostics.report(error, stage: .accountCheck)
            throw error
        }
        CompanionDebugLog.write("iCloud account status: \(status.rawValue)")
        guard status == .available else {
            throw CompanionSharingError.iCloudAccountUnavailable
        }
    }

    func modifyRecords(
        in database: CKDatabase,
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID] = [],
        diagnosticsStage: CompanionCloudDiagnostics.Stage? = nil
    ) async throws -> [CKRecord] {
        do {
            let result = try await database.modifyRecords(
                saving: records, deleting: recordIDs,
                savePolicy: .ifServerRecordUnchanged, atomically: true
            )
            // The operation can succeed while individual records fail. Unwrap every
            // result so schema/permission errors cannot become a missing-share error.
            var saved: [CKRecord] = []
            for record in records {
                guard let recordResult = result.saveResults[record.recordID] else {
                    throw CompanionSharingError.sharePreparationFailed
                }
                saved.append(try recordResult.get())
            }
            for recordID in recordIDs {
                guard let deleteResult = result.deleteResults[recordID] else {
                    throw CompanionSharingError.sharePreparationFailed
                }
                try deleteResult.get()
            }
            return saved
        } catch {
            if let diagnosticsStage { CompanionCloudDiagnostics.report(error, stage: diagnosticsStage) }
            throw Self.mapError(error)
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
            return fallback
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

    /// Names of accepted members other than the current iCloud user. For the owner,
    /// this yields accepted companions. For a participant, it also includes
    /// the owner so later refreshes retain the complete visible companion group.
    static func participantNames(from share: CKShare, excludingOwner: Bool = false) -> [String] {
        let currentID = share.currentUserParticipant?.participantID
        CompanionDebugLog.write("share.participants: \(share.participants.map { "r=\($0.role.rawValue),s=\($0.acceptanceStatus.rawValue),c=\(String(describing: $0.userIdentity.nameComponents))" })")
        return CompanionNameList.normalized(share.participants.compactMap { participant in
            guard participant.acceptanceStatus == .accepted else { return nil }
            if excludingOwner, participant.role == .owner { return nil }
            if let currentID, participant.participantID == currentID { return nil }
            return displayName(for: participant) ?? BSLocalization.text("朋友")
        })
    }

    static func displayName(for participant: CKShare.Participant) -> String? {
        displayName(for: participant.userIdentity)
    }

    static func displayName(for identity: CKUserIdentity) -> String? {
        if let components = identity.nameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty { return formatted }
            let pieces = [components.familyName, components.givenName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !pieces.isEmpty {
                return pieces.joined()
            }
            if let nickname = components.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
                return nickname
            }
        }
        if let email = identity.lookupInfo?.emailAddress {
            let prefix = email.split(separator: "@").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prefix, !prefix.isEmpty { return prefix }
        }
        if let phone = identity.lookupInfo?.phoneNumber {
            let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    static func snapshot(
        from record: CKRecord,
        shareLocator: CompanionRecordLocator?,
        forcedStatus: CompanionCloudStatus? = nil,
        participantDisplayNames: [String] = [],
        share: CKShare? = nil
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

        let legacyShow = CompanionShowSnapshot(
            showID: showID,
            showName: showName,
            showDate: showDate,
            showStartTime: showStartTime,
            showLocation: record[CompanionSessionRecord.showLocation] as? String
        )

        let showSnapshot: CompanionShowSnapshot
        if let data = record[CompanionSessionRecord.showSnapshotV1] as? Data {
            do {
                let decoded = try JSONDecoder().decode(CompanionShowSnapshot.self, from: data)
                guard decoded.schemaVersion <= CompanionShowSnapshot.currentSchemaVersion,
                      !decoded.showID.isEmpty,
                      !decoded.showName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CompanionSharingError.invalidPayload
                }
                showSnapshot = decoded
            } catch let error as CompanionSharingError {
                throw error
            } catch {
                CompanionDebugLog.write("Decoding frozen companion show snapshot failed: \(error)")
                throw CompanionSharingError.invalidPayload
            }
        } else {
            // Invitations created before the full-snapshot rollout remain valid.
            showSnapshot = legacyShow
        }

        var ownerCompanions: [CompanionMember]? = nil
        var participantCompanions: [CompanionMember]? = nil
        var directMembers: [CompanionMember]? = nil

        if let share {
            let nicknames = CompanionNicknamesSerialization.decode(
                from: record[CompanionSessionRecord.participantNicknamesJSON] as? String
            )
            let currentParticipantID = share.currentUserParticipant?.participantID
            let acceptedNonOwners = share.participants.filter {
                $0.role != .owner && $0.acceptanceStatus == .accepted
            }

            let builtOwnerCompanions: [CompanionMember] = acceptedNonOwners.map { participant in
                let pid = participant.participantID
                let name = nicknames[pid]
                    ?? Self.displayName(for: participant)
                    ?? (record[CompanionSessionRecord.participantDisplayName] as? String)
                    ?? BSLocalization.text("朋友")
                return CompanionMember(id: pid, name: name)
            }
            ownerCompanions = builtOwnerCompanions

            let ownerPID = share.owner.participantID
            let ownerName = (record[CompanionSessionRecord.ownerDisplayName] as? String)
                ?? Self.displayName(for: share.owner)
                ?? BSLocalization.text("同行者")
            let ownerMember = CompanionMember(id: ownerPID, name: ownerName)

            let otherNonOwners: [CompanionMember] = acceptedNonOwners.compactMap { participant in
                if let currentParticipantID, participant.participantID == currentParticipantID {
                    return nil
                }
                let pid = participant.participantID
                let name = nicknames[pid]
                    ?? Self.displayName(for: participant)
                    ?? BSLocalization.text("朋友")
                return CompanionMember(id: pid, name: name)
            }
            participantCompanions = [ownerMember] + otherNonOwners
            directMembers = builtOwnerCompanions
        }

        return CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(recordID: record.recordID),
            shareLocator: shareLocator,
            show: showSnapshot,
            ownerDisplayName: record[CompanionSessionRecord.ownerDisplayName] as? String,
            participantDisplayName: record[CompanionSessionRecord.participantDisplayName] as? String,
            participantDisplayNames: CompanionNameList.normalized(participantDisplayNames),
            status: status,
            createdAt: createdAt,
            acceptedAt: record[CompanionSessionRecord.acceptedAt] as? Date,
            canceledAt: record[CompanionSessionRecord.canceledAt] as? Date,
            members: directMembers,
            ownerCompanions: ownerCompanions,
            participantCompanions: participantCompanions
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
