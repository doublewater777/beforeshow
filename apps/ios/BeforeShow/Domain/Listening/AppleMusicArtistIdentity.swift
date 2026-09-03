import Foundation

enum AppleMusicArtistIdentity {
    static func artistID(from rawURL: String?) -> String? {
        guard let rawURL,
              let url = URL(string: rawURL),
              url.host?.lowercased() == "music.apple.com",
              let last = url.pathComponents.last,
              !last.isEmpty,
              last.allSatisfy(\.isNumber) else {
            return nil
        }
        return last
    }
}
