import CloudKit
import Foundation

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
            showLocation: locationParts.isEmpty ? nil : locationParts.joined(separator: " · "),
            sourceShowDate: show.date,
            showEndDate: show.endDate,
            showEndTime: show.endTime,
            timeZoneSecondsFromGMT: show.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: show.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: show.timeZoneIdentifier,
            endTimeZoneIdentifier: show.endTimeZoneIdentifier,
            city: show.city,
            venueName: show.venueName,
            venueAddress: show.venueAddress,
            artists: show.artists.map {
                CompanionArtistSnapshot(
                    name: $0.name,
                    avatarURL: $0.avatarURL,
                    appleMusicURL: $0.appleMusicURL,
                    appleMusicArtistID: $0.appleMusicArtistID,
                    albumArtworkURL: $0.albumArtworkURL
                )
            },
            // Local file:// covers are device-private and meaningless to recipients.
            coverImageURL: Self.portableRemoteURLString(show.coverImageURL),
            showChangeStatusRawValue: show.changeStatus.rawValue,
            postponedDate: show.postponedDate
        )
    }

    var artistSlots: [ArtistSlot] {
        artists.map {
            ArtistSlot(
                name: $0.name,
                avatarURL: $0.avatarURL,
                appleMusicURL: $0.appleMusicURL,
                appleMusicArtistID: $0.appleMusicArtistID,
                albumArtworkURL: $0.albumArtworkURL
            )
        }
    }

    private static func portableRemoteURLString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return trimmed
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
        if isOwner, snapshot.status == .accepted {
            resolvedNames = cloudNames
        } else if !cloudNames.isEmpty {
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
