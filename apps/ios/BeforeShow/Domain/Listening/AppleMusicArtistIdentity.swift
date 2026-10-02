import Foundation

enum AppleMusicArtistIdentity {
    static func artistID(from rawURL: String?) -> String? {
        guard let rawURL,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "music.apple.com",
              let artistIndex = url.pathComponents.firstIndex(of: "artist"),
              artistIndex == 1 || artistIndex == 2,
              artistIndex == 1 || (url.pathComponents[1].utf8.count == 2
                && url.pathComponents[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })),
              (1...2).contains(url.pathComponents.count - artistIndex - 1),
              let last = url.pathComponents.last,
              !last.isEmpty,
              last.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return nil
        }
        return last
    }

    static func artistID(for slot: ArtistSlot) -> String? {
        if let id = slot.appleMusicArtistID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return artistID(from: slot.appleMusicURL)
    }
}
