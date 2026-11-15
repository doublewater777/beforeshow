import Foundation

/// One credited artist on a disc, linked to Apple Music when its ID is known.
struct ListeningDiscArtistLink: Identifiable, Equatable {
    let name: String
    let artistID: String?

    var id: String { artistID ?? name }

    /// Artist page in the given storefront, or an Apple Music search by name.
    func appleMusicURL(storefront: String?) -> URL? {
        if let artistID {
            let region = storefront.map { "/" + $0.lowercased() } ?? ""
            return URL(string: "https://music.apple.com\(region)/artist/\(artistID)")
        }
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: name)]
        return components?.url
    }
}

enum ListeningDiscArtistLinks {
    /// Album credits come with aligned IDs; playlists and compilations fall back to
    /// the playlist's own artist and then the show lineup, matched by name.
    static func links(for disc: ListeningDisc, lineup: [ArtistSlot]) -> [ListeningDiscArtistLink] {
        let names = disc.artistNames.isEmpty
            ? Array(Set(disc.tracks.map(\.artistName))).sorted()
            : disc.artistNames
        let creditedIDs = disc.artistIDs.flatMap { $0.count == names.count ? $0 : nil }
        let lineupIDs = Dictionary(
            lineup.compactMap { slot in
                AppleMusicArtistIdentity.artistID(for: slot).map { (ArtistNameMatching.normalized(slot.name), $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        return names.enumerated().map { index, name in
            var artistID = creditedIDs?[index]
            if artistID == nil, names.count == 1, case let .featuredPlaylist(id) = disc.origin {
                artistID = id
            }
            if artistID == nil {
                artistID = lineupIDs[ArtistNameMatching.normalized(name)]
            }
            return ListeningDiscArtistLink(name: name, artistID: artistID?.isEmpty == false ? artistID : nil)
        }
    }

    /// The connected lineup artist a credit names, whose in-app page it opens; others go to Apple Music.
    /// A credit with its own Apple Music ID matches by ID only, so a namesake never opens the wrong page.
    static func lineupArtist(for link: ListeningDiscArtistLink, in artists: [ListeningBrowseArtist]) -> ListeningBrowseArtist? {
        let connected = artists.filter(\.isConnected)
        if let artistID = link.artistID {
            return connected.first { $0.appleMusicArtistID == artistID }
        }
        let name = ArtistNameMatching.normalized(link.name)
        return connected.first { ArtistNameMatching.normalized($0.name) == name }
    }
}
