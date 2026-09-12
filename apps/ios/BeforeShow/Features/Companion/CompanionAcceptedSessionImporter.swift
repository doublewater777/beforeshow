import Foundation
import SwiftData

struct CompanionAcceptedImportResult: Equatable {
    let showID: UUID
    let inserted: Bool
    let becameCurrent: Bool
    let wasHistorical: Bool
}

@MainActor
enum CompanionAcceptedSessionImporter {
    @discardableResult
    static func apply(
        _ session: CompanionSessionSnapshot,
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> CompanionAcceptedImportResult {
        let descriptor = FetchDescriptor<Show>()
        var shows = try modelContext.fetch(descriptor)

        // Freeze unresolved legacy origins before an accepted share can mark a local show
        // as participant-side and make its original provenance ambiguous.
        ShowCreationOriginMigration.resolveUnresolvedOrigins(in: shows)

        if let existing = shows.first(where: {
            $0.companionCloudRecordName == session.sessionLocator.recordName
        }) {
            mergeMissingShowData(from: session.show, into: existing)
            existing.applyCompanionSession(session, isOwner: false)
            let becameCurrent = try selectAsCurrentIfNeeded(existing, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: existing, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        if let sourceID = UUID(uuidString: session.show.showID),
           let byID = shows.first(where: { $0.id == sourceID }) {
            mergeMissingShowData(from: session.show, into: byID)
            byID.applyCompanionSession(session, isOwner: false)
            let becameCurrent = try selectAsCurrentIfNeeded(byID, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: byID, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        let candidate = try makeShow(from: session.show)
        let duplicateCandidates = shows.filter { existing in
            // One local Show owns at most one companion group. Never overwrite linkage
            // from an unrelated session just because the show metadata looks similar.
            guard existing.companionCloudRecordName == nil else { return false }
            return ShowDuplicateMatcher.isDuplicate(candidate, existing)
        }

        if duplicateCandidates.count == 1, let match = duplicateCandidates.first {
            mergeMissingShowData(from: session.show, into: match)
            match.applyCompanionSession(session, isOwner: false)
            let becameCurrent = try selectAsCurrentIfNeeded(match, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: match, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        // Ambiguous local matches are intentionally not overwritten. Until the dedicated
        // chooser UI resolves that edge case, creating the accepted copy is safer than
        // mutating the wrong user-owned Show.
        candidate.applyCompanionSession(session, isOwner: false)
        modelContext.insert(candidate)
        shows.append(candidate)

        let state = CurrentShowTimeState(show: candidate, now: now)
        if state.kind == .ended {
            // A historical companion import belongs in footprints and must never steal Current.
            candidate.markAddedAsHistorical()
        }

        let becameCurrent = try selectAsCurrentIfNeeded(candidate, among: shows, in: modelContext, now: now)
        try modelContext.save()
        return result(for: candidate, inserted: true, becameCurrent: becameCurrent, now: now)
    }

    private static func makeShow(from snapshot: CompanionShowSnapshot) throws -> Show {
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
            show.markPostponed(newDate: snapshot.postponedDate ?? snapshot.showDate)
        }
        return show
    }

    /// A companion invite is a one-time import. Existing local values win; the frozen
    /// snapshot only fills missing fields, except for objective postponed/canceled state.
    private static func mergeMissingShowData(
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
                show.markPostponed(newDate: snapshot.postponedDate ?? snapshot.showDate)
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

    private static func selectAsCurrentIfNeeded(
        _ show: Show,
        among shows: [Show],
        in modelContext: ModelContext,
        now: Date
    ) throws -> Bool {
        // Production includes CurrentShowSelection in the app schema. Some lightweight
        // recovery/unit-test containers intentionally model only Show; importing the Show
        // should still succeed there instead of failing the accepted-share recovery.
        guard modelContext.container.schema.entity(for: CurrentShowSelection.self) != nil else {
            return false
        }

        let store = CurrentShowSelectionStore(modelContext: modelContext)
        let selection = try store.canonicalSelection()
        let current = CurrentShowSession().selectCurrentShow(
            from: shows,
            manualSelection: selection,
            now: now
        )
        guard current == nil,
              show.wasAddedAsHistorical != true,
              CurrentShowTimeState(show: show, now: now).isAutomaticallySelectable else {
            return false
        }
        _ = try store.select(showID: show.id)
        return true
    }

    private static func result(
        for show: Show,
        inserted: Bool,
        becameCurrent: Bool,
        now: Date
    ) -> CompanionAcceptedImportResult {
        CompanionAcceptedImportResult(
            showID: show.id,
            inserted: inserted,
            becameCurrent: becameCurrent,
            wasHistorical: show.wasAddedAsHistorical == true
                || CurrentShowTimeState(show: show, now: now).kind == .ended
        )
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
