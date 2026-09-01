import Foundation
import SwiftData

@MainActor
enum CompanionAcceptedSessionImporter {
    static func apply(
        _ session: CompanionSessionSnapshot,
        in modelContext: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<Show>()
        let shows = try modelContext.fetch(descriptor)

        // Freeze unresolved legacy origins before an accepted share can mark a local show
        // as participant-side and make its original provenance ambiguous.
        ShowCreationOriginMigration.resolveUnresolvedOrigins(in: shows)

        if let existing = shows.first(where: {
            $0.companionCloudRecordName == session.sessionLocator.recordName
        }) {
            existing.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        if let byID = shows.first(where: { $0.id.uuidString == session.show.showID }) {
            byID.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        let calendar = Calendar.current
        let location = session.show.showLocation
        let parts = location?.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        let venue: String? = parts.first.map { String($0) }
        let city: String? = parts.count > 1 ? parts.last.map { String($0) } : nil

        let candidates = shows.filter { candidate in
            guard candidate.companionStatus == .none else { return false }
            guard candidate.name == session.show.showName else { return false }
            guard calendar.isDate(candidate.effectiveDate, inSameDayAs: session.show.showDate) else {
                return false
            }
            if let venue {
                guard let candidateVenue = candidate.venueName,
                      !candidateVenue.isEmpty,
                      candidateVenue == venue else {
                    return false
                }
            }
            if let city {
                guard let candidateCity = candidate.city,
                      !candidateCity.isEmpty,
                      candidateCity == city else {
                    return false
                }
            }
            let delta = abs(candidate.startTime.timeIntervalSince(session.show.showStartTime))
            return delta <= 60
        }

        if candidates.count == 1, let match = candidates.first {
            match.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        let show = try Show(
            name: session.show.showName,
            date: session.show.showDate,
            startTime: session.show.showStartTime,
            city: city.flatMap { $0.isEmpty ? nil : $0 },
            venueName: venue.flatMap { $0.isEmpty ? nil : $0 },
            creationOrigin: .companionImport
        )
        show.applyCompanionSession(session, isOwner: false)
        modelContext.insert(show)
        try modelContext.save()
    }
}
