import SwiftUI

struct ListeningSleeveIdentity {
    let disc: ListeningDisc
    var show: Show?

    /// Show playlists take colors in order so no two side by side match; other records hash their ID.
    private var index: Int {
        let count = BSListeningTokens.sleevePalette.count
        if case let .compilation(_, number) = disc.origin { return (max(number, 1) - 1) % count }
        return disc.id.utf8.reduce(0) { ($0 + Int($1)) % count }
    }

    var color: Color { BSListeningTokens.sleevePalette[index] }
    var title: String {
        disc.title
    }
    var artworkURL: URL? {
        if case .compilation = disc.origin {
            return show?.coverImageURL.flatMap(URL.init(string:))
                ?? show?.artists.compactMap { $0.avatarURL.flatMap(URL.init(string:)) }.first
        }
        return disc.artworkURL
    }
}
