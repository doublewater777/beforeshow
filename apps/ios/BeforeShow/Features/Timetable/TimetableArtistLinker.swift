import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TimetableArtistLinker {
    @ObservationIgnored private let search: any ArtistSearchServicing
    @ObservationIgnored private var searchResults: [String: [RecognizedArtist]] = [:]
    private var knownArtists: [RecognizedArtist] = []

    init(search: any ArtistSearchServicing = AppleMusicArtistSearchService()) {
        self.search = search
    }

    var avatarLineup: [ArtistSlot] {
        knownArtists.map {
            ArtistSlot(name: $0.canonicalName, avatarURL: $0.avatarURL?.absoluteString,
                       appleMusicArtistID: $0.id)
        }
    }

    func loadKnownArtists(in context: ModelContext) throws {
        let shows = try context.fetch(FetchDescriptor<Show>())
        let performances = try context.fetch(FetchDescriptor<TimetablePerformance>())
        knownArtists = shows.flatMap(\.artists).compactMap { slot in
            guard let id = AppleMusicArtistIdentity.artistID(for: slot) else { return nil }
            return RecognizedArtist(id: id, canonicalName: slot.name,
                                    avatarURL: slot.avatarURL.flatMap(URL.init(string:)),
                                    appleMusicURL: slot.appleMusicURL.flatMap(URL.init(string:)))
        } + performances.compactMap { performance in
            guard let id = performance.appleMusicArtistID else { return nil }
            return RecognizedArtist(id: id, canonicalName: performance.artistName,
                                    avatarURL: performance.artistAvatarURL.flatMap(URL.init(string:)),
                                    appleMusicURL: nil)
        }
    }

    func candidates(for query: String) async throws -> [RecognizedArtist] {
        let known = existingMatches(for: query)
        if !known.isEmpty { return known }
        let key = ArtistNameMatching.normalized(query)
        if let cached = searchResults[key] { return cached }
        let found = try await search.searchArtists(query: query)
        try Task.checkCancellation()
        searchResults[key] = found
        return found
    }

    func rememberConnectedArtist(_ artist: RecognizedArtist) {
        knownArtists.append(artist)
    }

    /// Only reuse an unambiguous saved identity when importing a new timetable.
    /// Editing a saved timetable never rebinds performances the user disconnected.
    func reuseKnownArtists(in draft: inout TimetableDraft) {
        for day in draft.days.indices {
            for stage in draft.days[day].stages.indices {
                for index in draft.days[day].stages[stage].performances.indices {
                    let performance = draft.days[day].stages[stage].performances[index]
                    guard performance.appleMusicArtistID == nil else { continue }
                    let matches = existingMatches(for: performance.artistName)
                    if matches.count == 1, let artist = matches.first {
                        draft.days[day].stages[stage].performances[index].connectArtist(artist)
                    }
                }
            }
        }
    }

    private func existingMatches(for name: String) -> [RecognizedArtist] {
        var matches: [RecognizedArtist] = []
        for (index, query) in TimetableArtistAvatarStore.candidateQueries(for: name).enumerated() {
            let normalized = ArtistNameMatching.normalized(query)
            for artist in knownArtists where ArtistNameMatching.normalized(artist.canonicalName) == normalized {
                if let index = matches.firstIndex(where: { $0.id == artist.id }) {
                    if matches[index].avatarURL == nil && artist.avatarURL != nil { matches[index] = artist }
                } else {
                    matches.append(artist)
                }
            }
            if index == 0 && !matches.isEmpty { return matches }
        }
        return matches
    }
}
