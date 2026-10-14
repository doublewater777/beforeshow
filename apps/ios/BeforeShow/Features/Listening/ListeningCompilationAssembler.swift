import Foundation

/// Catalog order is the only ranking input. Packing never changes an artist's song order.
enum ListeningCompilationAssembler {
    enum Theme: String, CaseIterable {
        case singalong, latest, deepCuts

        var title: String {
            switch self {
            case .singalong: ListeningCopy.text("大合唱")
            case .latest: ListeningCopy.text("新歌")
            case .deepCuts: ListeningCopy.text("深挖")
            }
        }
    }

    /// One performance: an artist's songs in rank order and the scheduled set length.
    struct LiveSet {
        let tracks: [ListeningDiscTrack]
        let duration: TimeInterval
    }

    /// A simulated show: sets play in schedule order, each filled to roughly its real length.
    struct LiveProgram {
        /// Stable identity, so a rebuilt rack never hands one album's ID to another.
        let key: String
        let title: String
        let sets: [LiveSet]
    }

    /// Hopping between stages: each chosen set plays until the next one starts.
    /// `sets` must be in start order; a set left with no time is dropped.
    static func route(_ sets: [(tracks: [ListeningDiscTrack], startsAt: Date, endsAt: Date)]) -> [LiveSet] {
        sets.indices.compactMap { index in
            let set = sets[index]
            let end = index + 1 < sets.count ? min(set.endsAt, sets[index + 1].startsAt) : set.endsAt
            let duration = end.timeIntervalSince(set.startsAt)
            return duration > 0 ? LiveSet(tracks: set.tracks, duration: duration) : nil
        }
    }

    static let maxTracksPerDisc = 20
    static let fallbackTrackDuration: TimeInterval = 210
    static let singleArtistTracksPerDisc = 10

    /// Live programs come first, in the order given.
    /// 大合唱 takes the top of the coverage-first stream; 新歌 takes the most recently
    /// released of the rest; 深挖 takes what remains in rank order. Empty themes are skipped.
    static func discs(
        showID: UUID,
        coverURL: URL? = nil,
        releaseDates: [String: Date] = [:],
        livePrograms: [LiveProgram] = [],
        artistTracks: [[ListeningDiscTrack]]
    ) -> [ListeningDisc] {
        let live: [Volume] = livePrograms.map { Volume(key: $0.key, title: $0.title, tracks: filled($0.sets)) }
        let activeArtists = artistTracks.filter { !$0.isEmpty }
        guard !activeArtists.isEmpty else { return numbered(live, showID: showID, coverURL: coverURL) }

        let capacity = activeArtists.count == 1 ? singleArtistTracksPerDisc : maxTracksPerDisc
        let stream = coverageFirstStream(from: activeArtists)

        let singalong = Array(stream.prefix(capacity))
        var rest = Array(stream.dropFirst(capacity))

        let dated: [(offset: Int, date: Date, item: Item)] = rest.enumerated().compactMap { offset, item in
            releaseDates[item.track.id].map { (offset, $0, item) }
        }
        let latest: [Item] = dated
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.offset < $1.offset }
            .prefix(capacity)
            .map { $0.item }
        let latestIDs = Set(latest.map(\.track.id))
        rest.removeAll { item in latestIDs.contains(item.track.id) }
        let deepCuts = Array(rest.prefix(capacity))

        let themed = [(Theme.singalong, singalong), (.latest, latest), (.deepCuts, deepCuts)].map { theme, items in
            Volume(key: theme.rawValue, title: theme.title, tracks: groupedByArtist(items))
        }
        return numbered(live + themed, showID: showID, coverURL: coverURL)
    }

    private struct Volume {
        let key: String
        let title: String
        let tracks: [ListeningDiscTrack]
    }

    private static func numbered(_ volumes: [Volume], showID: UUID, coverURL: URL? = nil) -> [ListeningDisc] {
        volumes.filter { !$0.tracks.isEmpty }.enumerated().map { index, volume in
            ListeningDisc(
                id: "compilation-\(showID)-\(volume.key)",
                title: volume.title,
                artworkURL: coverURL,
                tracks: volume.tracks,
                origin: .compilation(showID: showID, number: index + 1)
            )
        }
    }

    /// Adds each artist's next song while doing so keeps the set closer to its scheduled length.
    private static func filled(_ sets: [LiveSet]) -> [ListeningDiscTrack] {
        var seen = Set<String>()
        var result: [ListeningDiscTrack] = []
        for set in sets {
            var total: TimeInterval = 0
            for track in set.tracks where !seen.contains(track.id) {
                let length = track.duration ?? fallbackTrackDuration
                guard total == 0 || total + length - set.duration < set.duration - total else { break }
                seen.insert(track.id)
                result.append(track)
                total += length
            }
        }
        return result
    }

    private typealias Item = (artistIndex: Int, track: ListeningDiscTrack)

    /// Every artist contributes its next top song before any artist advances another rank.
    private static func coverageFirstStream(from artists: [[ListeningDiscTrack]]) -> [Item] {
        var cursors = Array(repeating: 0, count: artists.count)
        var seenSongIDs = Set<String>()
        var selected: [Item] = []

        while true {
            var addedInRound = false
            for artistIndex in artists.indices {
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
            if !addedInRound { return selected }
        }
    }

    /// Tracks from the same artist sit together without changing their relative order.
    private static func groupedByArtist(_ items: [Item]) -> [ListeningDiscTrack] {
        var artistOrder: [Int] = []
        var grouped: [Int: [ListeningDiscTrack]] = [:]
        for item in items {
            if grouped[item.artistIndex] == nil { artistOrder.append(item.artistIndex) }
            grouped[item.artistIndex, default: []].append(item.track)
        }
        return artistOrder.flatMap { grouped[$0] ?? [] }
    }
}
