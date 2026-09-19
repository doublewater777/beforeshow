import Foundation

/// Catalog order is the only ranking input. Packing never changes song order.
enum ListeningCompilationAssembler {
    static let maxDiscCount = 9
    static let tracksPerArtistPerDisc = 2

    static func discs(showID: UUID, artistTracks: [[ListeningDiscTrack]]) -> [ListeningDisc] {
        var seen = Set<String>()
        var batches: [[ListeningDiscTrack]] = []

        for discIndex in 0..<maxDiscCount {
            var batch: [ListeningDiscTrack] = []
            let firstTrackIndex = discIndex * tracksPerArtistPerDisc

            for offset in 0..<tracksPerArtistPerDisc {
                let trackIndex = firstTrackIndex + offset
                for tracks in artistTracks where tracks.indices.contains(trackIndex) {
                    let track = tracks[trackIndex]
                    if seen.insert(track.id).inserted {
                        batch.append(track)
                    }
                }
            }

            if !batch.isEmpty {
                batches.append(batch)
            }
        }

        return batches.enumerated().map { index, tracks in
            ListeningDisc(id: "compilation-\(showID)-\(index + 1)",
                          title: BSLocalization.format("热门合辑 %02d", index + 1),
                          artworkURL: nil, tracks: tracks,
                          origin: .compilation(showID: showID, number: index + 1))
        }
    }
}
