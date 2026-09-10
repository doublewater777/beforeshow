import SwiftUI

struct ListeningSleeveIdentity {
    let disc: ListeningDisc
    var show: Show?

    private var index: Int {
        disc.id.utf8.reduce(0) { ($0 + Int($1)) % BSListeningTokens.sleevePalette.count }
    }

    var color: Color { BSListeningTokens.sleevePalette[index] }
    var angle: Double { BSListeningTokens.sleeveAngles[index] }
    var title: String {
        if case .compilation = disc.origin { return show?.name ?? disc.title }
        return disc.title
    }
    var artworkURL: URL? {
        if case .compilation = disc.origin {
            return show?.coverImageURL.flatMap(URL.init(string:))
                ?? show?.artists.compactMap { $0.avatarURL.flatMap(URL.init(string:)) }.first
        }
        return disc.artworkURL
    }
}
