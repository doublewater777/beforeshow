import Foundation

enum FootprintAlbumArtworkWriteback {
    @MainActor
    @discardableResult
    static func persist(
        _ url: URL,
        artistName: String,
        showIDs: [UUID],
        in shows: [Show]
    ) -> Bool {
        guard let trimmed = FootprintTextNormalizer.nonEmptyTrimmed(artistName) else { return false }
        var changed = false
        for show in shows where showIDs.contains(show.id) {
            for index in show.artists.indices {
                guard FootprintTextNormalizer.nonEmptyTrimmed(show.artists[index].name) == trimmed,
                      show.artists[index].albumArtworkURL == nil else { continue }
                show.artists[index].albumArtworkURL = url.absoluteString
                changed = true
            }
        }
        return changed
    }
}
