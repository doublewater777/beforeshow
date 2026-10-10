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

    func candidates(for query: String, includingRemote: Bool = false) async throws -> [RecognizedArtist] {
        let known = savedCandidates(for: query)
        if !includingRemote && !known.isEmpty { return known }
        let key = ArtistNameMatching.normalized(query)
        let found: [RecognizedArtist]
        if let cached = searchResults[key] {
            found = cached
        } else {
            found = try await search.searchArtists(query: query)
            try Task.checkCancellation()
            searchResults[key] = found
        }
        var merged = known
        var identities = Set(known.map(\.id))
        for artist in found where identities.insert(artist.id).inserted { merged.append(artist) }
        return merged
    }

    func rememberConnectedArtist(_ artist: RecognizedArtist) {
        knownArtists.append(artist)
    }

    /// Automatically search and match artist IDs for all unlinked performers in a draft.
    func autoMatchArtists(in draft: inout TimetableDraft) async {
        reuseKnownArtists(in: &draft)
        var slots: [ArtistSlot] = []
        var paths: [(dayIndex: Int, stageIndex: Int, perfIndex: Int)] = []

        for d in draft.days.indices {
            for s in draft.days[d].stages.indices {
                for p in draft.days[d].stages[s].performances.indices {
                    let perf = draft.days[d].stages[s].performances[p]
                    if perf.appleMusicArtistID == nil && !perf.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        slots.append(ArtistSlot(name: perf.artistName, avatarURL: nil))
                        paths.append((d, s, p))
                    }
                }
            }
        }

        guard !slots.isEmpty else { return }
        let matcher = ArtistIdentityMatcher(search: search)
        if let matches = try? await matcher.matches(for: slots) {
            for (index, artist) in matches {
                let (d, s, p) = paths[index]
                draft.days[d].stages[s].performances[p].connectArtist(artist)
                rememberConnectedArtist(artist)
            }
        }
    }

    /// Automatically match unlinked performances in a persisted Timetable.
    func autoMatchPersistedPerformances(in timetable: Timetable, context: ModelContext) async {
        var slots: [ArtistSlot] = []
        var perfs: [TimetablePerformance] = []

        for day in timetable.days {
            for stage in day.stages {
                for perf in stage.performances {
                    if perf.appleMusicArtistID == nil && !perf.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        slots.append(ArtistSlot(name: perf.artistName, avatarURL: nil))
                        perfs.append(perf)
                    }
                }
            }
        }

        guard !slots.isEmpty else { return }
        let matcher = ArtistIdentityMatcher(search: search)
        guard let matches = try? await matcher.matches(for: slots), !matches.isEmpty else { return }

        for (index, artist) in matches {
            perfs[index].connectArtist(artist)
            rememberConnectedArtist(artist)
        }
        try? context.save()
    }

    /// Only reuse an unambiguous saved identity when importing a new timetable.
    /// Editing a saved timetable never rebinds performances the user disconnected.
    func reuseKnownArtists(in draft: inout TimetableDraft) {
        for day in draft.days.indices {
            for stage in draft.days[day].stages.indices {
                for index in draft.days[day].stages[stage].performances.indices {
                    let performance = draft.days[day].stages[stage].performances[index]
                    guard performance.appleMusicArtistID == nil else { continue }
                    let matches = savedCandidates(for: performance.artistName)
                    if matches.count == 1, let artist = matches.first {
                        draft.days[day].stages[stage].performances[index].connectArtist(artist)
                    }
                }
            }
        }
    }

    func savedCandidates(for name: String) -> [RecognizedArtist] {
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
