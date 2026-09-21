import Foundation

/// Catalog order is the only ranking input. Packing never changes song order.
enum ListeningCompilationAssembler {
    static let maxDiscCount = 9
    static let tracksPerArtistPerDisc = 2
    static let singleArtistTracksPerDisc = 10
    static let singleArtistMaxDiscCount = 3

    static func discs(showID: UUID, artistTracks: [[ListeningDiscTrack]]) -> [ListeningDisc] {
        let activeArtists = artistTracks.filter { !$0.isEmpty }
        guard !activeArtists.isEmpty else { return [] }

        var batches: [[ListeningDiscTrack]] = []

        if activeArtists.count == 1 {
            var seen = Set<String>()
            var uniqueTracks: [ListeningDiscTrack] = []
            for tracks in artistTracks {
                for track in tracks {
                    if seen.insert(track.id).inserted {
                        uniqueTracks.append(track)
                    }
                }
            }

            guard !uniqueTracks.isEmpty else { return [] }

            let discCount = min(
                singleArtistMaxDiscCount,
                (uniqueTracks.count + singleArtistTracksPerDisc - 1) / singleArtistTracksPerDisc
            )

            for discIndex in 0..<discCount {
                let start = discIndex * singleArtistTracksPerDisc
                let end = min(start + singleArtistTracksPerDisc, uniqueTracks.count)
                if start < end {
                    batches.append(Array(uniqueTracks[start..<end]))
                }
            }
        } else {
            var seen = Set<String>()

            for discIndex in 0..<maxDiscCount {
                var batch: [ListeningDiscTrack] = []
                let firstTrackIndex = discIndex * tracksPerArtistPerDisc

                for tracks in artistTracks {
                    for offset in 0..<tracksPerArtistPerDisc {
                        let trackIndex = firstTrackIndex + offset
                        guard tracks.indices.contains(trackIndex) else { continue }
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
        }

        return batches.enumerated().map { index, tracks in
            ListeningDisc(id: "compilation-\(showID)-\(index + 1)",
                          title: BSLocalization.format("热门合辑 %02d", index + 1),
                          artworkURL: nil, tracks: tracks,
                          origin: .compilation(showID: showID, number: index + 1))
        }
    }
}
