import Foundation

/// Catalog order is the only ranking input. Packing never changes an artist's song order.
enum ListeningCompilationAssembler {
    static let maxDiscCount = 3
    static let maxTracksPerDisc = 20
    static let maxMultiArtistTrackCount = maxDiscCount * maxTracksPerDisc
    static let singleArtistTracksPerDisc = 10
    static let singleArtistMaxDiscCount = 3

    static func discs(showID: UUID, artistTracks: [[ListeningDiscTrack]]) -> [ListeningDisc] {
        let activeArtists = artistTracks.filter { !$0.isEmpty }
        guard !activeArtists.isEmpty else { return [] }

        let batches: [[ListeningDiscTrack]]
        if activeArtists.count == 1 {
            batches = singleArtistBatches(from: activeArtists[0])
        } else {
            batches = multiArtistBatches(from: activeArtists)
        }

        return batches.enumerated().map { index, tracks in
            ListeningDisc(
                id: "compilation-\(showID)-\(index + 1)",
                title: BSLocalization.format("热门合辑 %02d", index + 1),
                artworkURL: nil,
                tracks: tracks,
                origin: .compilation(showID: showID, number: index + 1)
            )
        }
    }

    private static func singleArtistBatches(
        from tracks: [ListeningDiscTrack]
    ) -> [[ListeningDiscTrack]] {
        var seen = Set<String>()
        let uniqueTracks = tracks.filter { seen.insert($0.id).inserted }
        guard !uniqueTracks.isEmpty else { return [] }

        let discCount = min(
            singleArtistMaxDiscCount,
            (uniqueTracks.count + singleArtistTracksPerDisc - 1) / singleArtistTracksPerDisc
        )

        return (0..<discCount).compactMap { discIndex in
            let start = discIndex * singleArtistTracksPerDisc
            let end = min(start + singleArtistTracksPerDisc, uniqueTracks.count)
            guard start < end else { return nil }
            return Array(uniqueTracks[start..<end])
        }
    }

    /// Select songs in coverage-first rounds: every artist gets a chance to
    /// contribute its next top song before any artist advances another rank.
    /// The selected stream is then split into bounded virtual records; tracks from
    /// the same artist are grouped within each record without changing that artist's
    /// Apple Music top-song order.
    private static func multiArtistBatches(
        from artists: [[ListeningDiscTrack]]
    ) -> [[ListeningDiscTrack]] {
        var cursors = Array(repeating: 0, count: artists.count)
        var seenSongIDs = Set<String>()
        var selected: [(artistIndex: Int, track: ListeningDiscTrack)] = []

        while selected.count < maxMultiArtistTrackCount {
            var addedInRound = false

            for artistIndex in artists.indices {
                guard selected.count < maxMultiArtistTrackCount else { break }
                let tracks = artists[artistIndex]

                while cursors[artistIndex] < tracks.count {
                    let track = tracks[cursors[artistIndex]]
                    cursors[artistIndex] += 1
                    guard seenSongIDs.insert(track.id).inserted else { continue }
                    selected.append((artistIndex, track))
                    addedInRound = true
                    break
                }
            }

            if !addedInRound { break }
        }

        var batches: [[ListeningDiscTrack]] = []
        for start in stride(from: 0, to: selected.count, by: maxTracksPerDisc) {
            let end = min(start + maxTracksPerDisc, selected.count)
            let slice = selected[start..<end]

            var artistOrder: [Int] = []
            var grouped: [Int: [ListeningDiscTrack]] = [:]
            for item in slice {
                if grouped[item.artistIndex] == nil {
                    artistOrder.append(item.artistIndex)
                    grouped[item.artistIndex] = []
                }
                grouped[item.artistIndex, default: []].append(item.track)
            }

            let batch = artistOrder.flatMap { grouped[$0] ?? [] }
            if !batch.isEmpty {
                batches.append(batch)
            }
        }

        return Array(batches.prefix(maxDiscCount))
    }
}
