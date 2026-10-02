import Foundation

enum FootprintAlbumArtworkWriteback {
    @MainActor
    @discardableResult
    static func persist(
        _ url: URL,
        artistName: String,
        artistID: String? = nil,
        showIDs: [UUID],
        in shows: [Show]
    ) -> Bool {
        guard let trimmed = FootprintTextNormalizer.nonEmptyTrimmed(artistName) else { return false }
        var changed = false
        for show in shows where showIDs.contains(show.id) {
            for index in show.artists.indices {
                guard ArtistNameMatching.normalized(show.artists[index].name) == ArtistNameMatching.normalized(trimmed),
                      AppleMusicArtistIdentity.artistID(for: show.artists[index]) == artistID,
                      show.artists[index].albumArtworkURL == nil else { continue }
                show.artists[index].albumArtworkURL = url.absoluteString
                changed = true
            }
        }
        return changed
    }
}
