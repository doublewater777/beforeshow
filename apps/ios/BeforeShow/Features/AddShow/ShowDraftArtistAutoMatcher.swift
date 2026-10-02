import Foundation

/// Imported lineups share the listening matcher, including its concurrency and identity rules.
@MainActor
struct ShowDraftArtistAutoMatcher {
    let search: any ArtistSearchServicing

    func matches(for slots: [ArtistSlot]) async -> [Int: RecognizedArtist] {
        (try? await ArtistIdentityMatcher(search: search).matches(for: slots)) ?? [:]
    }
}
