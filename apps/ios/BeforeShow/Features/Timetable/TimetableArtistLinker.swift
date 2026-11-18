import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TimetableArtistLinker {
    @ObservationIgnored private let search: any ArtistSearchServicing
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
        let known = ArtistNameMatching.searchCandidates(savedCandidates(for: query))
        let found = try await search.searchInteractiveArtists(query: query)
        return ArtistNameMatching.searchCandidates(known + found)
    }

    func rememberConnectedArtist(_ artist: RecognizedArtist) {
        knownArtists.append(artist)
    }

    /// Automatically match unlinked performances in a persisted Timetable.
    func autoMatchPersistedPerformances(in timetable: Timetable, context: ModelContext) async {
        // The show's lineup is matched first (add show, 听); unlinked sets reuse it before any search.
        let lineup = timetable.show?.artists ?? []
        var adopted = false
        for performance in timetable.days.flatMap(\.performances) where performance.appleMusicArtistID == nil {
            adopted = performance.adoptLineupIdentity(from: lineup) || adopted
        }
        if adopted { try? context.save() }

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
        guard let matches = try? await matcher.matches(for: slots), !Task.isCancelled else { return }

        var matched = false
        for (index, artist) in matches {
            let performance = perfs[index]
            guard !performance.isDeleted,
                  performance.stage?.day?.timetable === timetable,
                  performance.artistName == slots[index].name,
                  performance.appleMusicArtistID == nil else { continue }
            performance.connectArtist(artist)
            rememberConnectedArtist(artist)
            matched = true
        }
        if matched { try? context.save() }
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
        // Resolve every script/bilingual form. Returning the first exact saved
        // name could hide another known Artist ID under an alternate credit.
        for query in ArtistNameMatching.nameVariants(for: name) {
            let normalized = ArtistNameMatching.normalized(query)
            for artist in knownArtists where ArtistNameMatching.normalized(artist.canonicalName) == normalized {
                if let index = matches.firstIndex(where: { $0.id == artist.id }) {
                    if matches[index].avatarURL == nil && artist.avatarURL != nil { matches[index] = artist }
                } else {
                    matches.append(artist)
                }
            }
        }
        return matches
    }
}
