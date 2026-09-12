import Foundation

@MainActor
enum CompanionAcceptedShowMapping {
    static func makeShow(from snapshot: CompanionShowSnapshot) throws -> Show {
        let legacyLocation = legacyLocationParts(snapshot.showLocation)
        let sourceDate = snapshot.sourceShowDate ?? snapshot.showDate
        let sourceID = UUID(uuidString: snapshot.showID) ?? UUID()
        let show = try Show(
            id: sourceID,
            name: snapshot.showName,
            date: sourceDate,
            startTime: snapshot.showStartTime,
            endDate: snapshot.showEndDate,
            endTime: snapshot.showEndTime,
            timeZoneSecondsFromGMT: snapshot.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: snapshot.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            endTimeZoneIdentifier: snapshot.endTimeZoneIdentifier,
            city: nonEmpty(snapshot.city) ?? legacyLocation.city,
            venueName: nonEmpty(snapshot.venueName) ?? legacyLocation.venue,
            venueAddress: nonEmpty(snapshot.venueAddress),
            artists: snapshot.artistSlots,
            coverImageURL: nonEmpty(snapshot.coverImageURL),
            changeStatus: snapshot.changeStatus,
            creationOrigin: .companionImport
        )

        if snapshot.changeStatus == .postponed {
            show.markPostponed(newDate: snapshot.postponedDate)
        }
        return show
    }

    /// Existing local values win. The frozen invite snapshot only fills missing fields,
    /// except for objective canceled/postponed state which is safe to carry over.
    static func mergeMissingData(
        from snapshot: CompanionShowSnapshot,
        into show: Show
    ) {
        let legacyLocation = legacyLocationParts(snapshot.showLocation)

        if show.endDate == nil { show.endDate = snapshot.showEndDate }
        if show.endTime == nil { show.endTime = snapshot.showEndTime }
        if show.timeZoneSecondsFromGMT == nil { show.timeZoneSecondsFromGMT = snapshot.timeZoneSecondsFromGMT }
        if show.endTimeZoneSecondsFromGMT == nil { show.endTimeZoneSecondsFromGMT = snapshot.endTimeZoneSecondsFromGMT }
        if nonEmpty(show.timeZoneIdentifier) == nil { show.timeZoneIdentifier = nonEmpty(snapshot.timeZoneIdentifier) }
        if nonEmpty(show.endTimeZoneIdentifier) == nil { show.endTimeZoneIdentifier = nonEmpty(snapshot.endTimeZoneIdentifier) }
        if nonEmpty(show.city) == nil { show.city = nonEmpty(snapshot.city) ?? legacyLocation.city }
        if nonEmpty(show.venueName) == nil { show.venueName = nonEmpty(snapshot.venueName) ?? legacyLocation.venue }
        if nonEmpty(show.venueAddress) == nil { show.venueAddress = nonEmpty(snapshot.venueAddress) }
        if nonEmpty(show.coverImageURL) == nil { show.coverImageURL = nonEmpty(snapshot.coverImageURL) }

        show.artists = mergeArtists(local: show.artists, incoming: snapshot.artistSlots)

        guard show.endedAt == nil else { return }
        switch snapshot.changeStatus {
        case .canceled:
            if show.changeStatus != .canceled {
                show.markCanceled()
            }
        case .postponed:
            if show.changeStatus == .scheduled {
                show.markPostponed(newDate: snapshot.postponedDate)
            }
        case .scheduled:
            break
        }
    }

    private static func mergeArtists(local: [ArtistSlot], incoming: [ArtistSlot]) -> [ArtistSlot] {
        var result = local
        for artist in incoming {
            if let index = result.firstIndex(where: { sameArtist($0, artist) }) {
                var existing = result[index]
                if nonEmpty(existing.avatarURL) == nil { existing.avatarURL = nonEmpty(artist.avatarURL) }
                if nonEmpty(existing.appleMusicURL) == nil { existing.appleMusicURL = nonEmpty(artist.appleMusicURL) }
                if nonEmpty(existing.appleMusicArtistID) == nil { existing.appleMusicArtistID = nonEmpty(artist.appleMusicArtistID) }
                if nonEmpty(existing.albumArtworkURL) == nil { existing.albumArtworkURL = nonEmpty(artist.albumArtworkURL) }
                result[index] = existing
            } else {
                result.append(artist)
            }
        }
        return result
    }

    private static func sameArtist(_ lhs: ArtistSlot, _ rhs: ArtistSlot) -> Bool {
        if let lhsID = nonEmpty(lhs.appleMusicArtistID),
           let rhsID = nonEmpty(rhs.appleMusicArtistID) {
            return lhsID == rhsID
        }
        return normalizedName(lhs.name) == normalizedName(rhs.name)
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func legacyLocationParts(_ raw: String?) -> (venue: String?, city: String?) {
        let parts = raw?.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        return (
            parts.first.flatMap { nonEmpty(String($0)) },
            parts.count > 1 ? nonEmpty(String(parts.last!)) : nil
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
