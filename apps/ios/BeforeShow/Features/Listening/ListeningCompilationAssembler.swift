import Foundation

/// Catalog order is the only ranking input. Packing never changes song order.
enum ListeningCompilationAssembler {
    static let targetDuration: TimeInterval = 75 * 60
    static let fallbackDuration: TimeInterval = 4 * 60

    static func discs(showID: UUID, artistTracks: [[ListeningDiscTrack]]) -> [ListeningDisc] {
        var seen = Set<String>()
        var ordered: [ListeningDiscTrack] = []
        for index in 0..<(artistTracks.map(\.count).max() ?? 0) {
            for tracks in artistTracks where tracks.indices.contains(index) {
                let track = tracks[index]
                if seen.insert(track.id).inserted { ordered.append(track) }
            }
        }
        var batches: [[ListeningDiscTrack]] = []
        var batch: [ListeningDiscTrack] = []
        var duration: TimeInterval = 0
        for track in ordered {
            let length = track.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallbackDuration
            if !batch.isEmpty, duration + length > targetDuration {
                batches.append(batch); batch = []; duration = 0
            }
            batch.append(track); duration += length
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches.enumerated().map { index, tracks in
            ListeningDisc(id: "compilation-\(showID)-\(index + 1)",
                          title: BSLocalization.format("热门合辑 %02d", index + 1),
                          artworkURL: nil, tracks: tracks,
                          origin: .compilation(showID: showID, number: index + 1))
        }
    }
}
