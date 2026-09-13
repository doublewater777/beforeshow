import Foundation

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
            postponedDate: show.postponedDate,
            endedAt: show.endedAt,
            wasAddedAsHistorical: show.wasAddedAsHistorical
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
