import CloudKit
import Foundation

// MARK: - Local show mapping

extension Show {
    /// Apply a CloudKit session onto local cache fields.
    /// Companion membership is append-only at the product layer: once a person has
    /// been recorded as a companion for this Show, refreshes never remove that fact.
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
        let existingNames = CompanionNameList.normalized(companionNames)

        let resolvedNames: [String]
        if snapshot.status == .accepted {
            resolvedNames = CompanionNameList.normalized(existingNames + cloudNames + fallback)
        } else if !cloudNames.isEmpty {
            resolvedNames = CompanionNameList.normalized(existingNames + cloudNames)
        } else if !fallback.isEmpty {
            resolvedNames = CompanionNameList.normalized(existingNames + fallback)
        } else {
            resolvedNames = existingNames
        }

        let resolvedStatus: ShowCompanionStatus
        if companionStatus == .confirmed, snapshot.status == .pending {
            // A CloudKit refresh can temporarily omit accepted participant state.
            // The product does not downgrade an already-recorded companion fact.
            resolvedStatus = .confirmed
        } else {
            resolvedStatus = snapshot.status.localStatus
        }

        applyCompanionState(status: resolvedStatus, names: resolvedNames)
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

extension Show {
    struct CompanionCloudLinkageSnapshot: Equatable {
        var record: String?
        var zone: String?
        var owner: String?
        var share: String?
        var shareZone: String?
        var shareOwner: String?
        var isOwner: Bool?
    }

    func companionCloudLinkageSnapshot() -> CompanionCloudLinkageSnapshot {
        CompanionCloudLinkageSnapshot(
            record: companionCloudRecordName,
            zone: companionCloudZoneName,
            owner: companionCloudOwnerName,
            share: companionShareRecordName,
            shareZone: companionShareZoneName,
            shareOwner: companionShareOwnerName,
            isOwner: companionIsOwner
        )
    }

    func restoreCompanionCloudLinkage(_ snapshot: CompanionCloudLinkageSnapshot) {
        companionCloudRecordName = snapshot.record
        companionCloudZoneName = snapshot.zone
        companionCloudOwnerName = snapshot.owner
        companionShareRecordName = snapshot.share
        companionShareZoneName = snapshot.shareZone
        companionShareOwnerName = snapshot.shareOwner
        companionIsOwner = snapshot.isOwner
    }
}
