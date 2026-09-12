import CloudKit
import Foundation

extension CloudKitCompanionSharingService {
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
        do {
            let snapshotData = try JSONEncoder().encode(show)
            session[CompanionSessionRecord.showSnapshotV1] = snapshotData as CKRecordValue
        } catch {
            CompanionDebugLog.write("Encoding frozen companion show snapshot failed: \(error)")
            throw CompanionSharingError.sharePreparationFailed
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
}
