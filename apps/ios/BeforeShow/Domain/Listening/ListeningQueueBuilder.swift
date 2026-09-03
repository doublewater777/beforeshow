import Foundation

struct ListeningQueueArtistInput: Equatable, Sendable {
    let artistID: String
    let orderedSongIDs: [String]
}

struct ListeningQueueEntry: Equatable, Sendable {
    let artistID: String
    let songID: String
}

enum ListeningQueueBuilder {
    static func build(
        artists: [ListeningQueueArtistInput],
        familiarSongIDs: Set<String>,
        excludedArtistIDs: Set<String> = [],
        onlyArtistID: String? = nil
    ) -> [ListeningQueueEntry] {
        var seenArtistIDs = Set<String>()
        let activeArtists = artists.filter { artist in
            guard !artist.artistID.isEmpty,
                  seenArtistIDs.insert(artist.artistID).inserted,
                  !excludedArtistIDs.contains(artist.artistID) else {
                return false
            }
            if let onlyArtistID {
                return artist.artistID == onlyArtistID
            }
            return true
        }

        let rankedByArtist = activeArtists.map { artist -> (String, [String]) in
            let stableIDs = deduplicated(artist.orderedSongIDs)
            let unfamiliar = stableIDs.filter { !familiarSongIDs.contains($0) }
            let familiar = stableIDs.filter { familiarSongIDs.contains($0) }
            return (artist.artistID, unfamiliar + familiar)
        }

        var positions = Array(repeating: 0, count: rankedByArtist.count)
        var emittedSongIDs = Set<String>()
        var result: [ListeningQueueEntry] = []
        var madeProgress = true

        while madeProgress {
            madeProgress = false
            for index in rankedByArtist.indices {
                let (artistID, songIDs) = rankedByArtist[index]
                while positions[index] < songIDs.count {
                    let songID = songIDs[positions[index]]
                    positions[index] += 1
                    if emittedSongIDs.insert(songID).inserted {
                        result.append(ListeningQueueEntry(artistID: artistID, songID: songID))
                        madeProgress = true
                        break
                    }
                }
            }
        }

        return result
    }

    private static func deduplicated(_ songIDs: [String]) -> [String] {
        var seen = Set<String>()
        return songIDs.filter { seen.insert($0).inserted }
    }
}
