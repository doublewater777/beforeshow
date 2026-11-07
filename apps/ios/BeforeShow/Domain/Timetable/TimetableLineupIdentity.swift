import Foundation

/// A timetable set and the show's lineup name the same artists; the lineup's Apple Music link wins
/// so the timetable, 听 and the artist page all open the same artist.
enum TimetableLineupIdentity {
    /// The one linked lineup slot this set's credit points to: the same name (any script or alias),
    /// or, failing that, the only linked slot whose name contains or is contained in the credit
    /// ("黄子弘凡 60min限定舞台" → 黄子弘凡, 回春丹 → 回春丹乐队).
    static func slot(for credit: String, in lineup: [ArtistSlot]) -> ArtistSlot? {
        let linked = lineup.filter { !($0.appleMusicArtistID ?? "").isEmpty }
        if let exact = unique(linked.filter { ArtistNameMatching.isConfidentMatch(credit, candidateName: $0.name) }) {
            return exact
        }
        let key = compact(credit)
        guard key.count >= 2 else { return nil }
        return unique(linked.filter { slot in
            let name = compact(slot.name)
            return name.count >= 2 && (key.contains(name) || name.contains(key))
        })
    }

    private static func compact(_ name: String) -> String {
        String(String.UnicodeScalarView(ArtistNameMatching.normalized(name).unicodeScalars.filter {
            !CharacterSet.whitespaces.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }))
    }

    private static func unique(_ slots: [ArtistSlot]) -> ArtistSlot? {
        guard let first = slots.first, Set(slots.compactMap(\.appleMusicArtistID)).count == 1 else { return nil }
        return first
    }
}

extension TimetablePerformance {
    /// Takes the lineup's link without renaming the set; returns whether anything changed.
    @discardableResult
    func adoptLineupIdentity(from lineup: [ArtistSlot]) -> Bool {
        guard let slot = TimetableLineupIdentity.slot(for: artistName, in: lineup),
              let id = slot.appleMusicArtistID, appleMusicArtistID != id else { return false }
        appleMusicArtistID = id
        if let avatar = slot.avatarURL, !avatar.isEmpty { artistAvatarURL = avatar }
        return true
    }
}

extension Show {
    /// Confirms a lineup artist's Apple Music match (appending when `index` is past the end),
    /// and moves the timetable's sets for that artist along with it.
    func relinkArtist(at index: Int, to artist: RecognizedArtist) {
        var lineup = artists
        if index == lineup.count { lineup.append(ArtistSlot(name: artist.canonicalName, avatarURL: nil)) }
        let previousName = lineup[index].name
        lineup[index].name = artist.canonicalName
        lineup[index].appleMusicArtistID = artist.id
        lineup[index].appleMusicURL = artist.appleMusicURL?.absoluteString
        lineup[index].avatarURL = artist.avatarURL?.absoluteString
        artists = lineup
        updatedAt = Date()

        var previous = lineup[index]
        previous.name = previousName
        for performance in (timetable?.days ?? []).flatMap(\.performances)
        where TimetableLineupIdentity.slot(for: performance.artistName, in: [lineup[index], previous]) != nil {
            performance.appleMusicArtistID = artist.id
            if let avatar = artist.avatarURL { performance.artistAvatarURL = avatar.absoluteString }
        }
    }
}
