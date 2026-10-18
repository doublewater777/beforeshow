import Foundation

// MARK: - 听搜索
// 只在当前现场唱片柜已有的唱片与歌曲里查找（唱片名、艺人、歌名，简繁/大小写不敏感）。

struct ListeningSearchResult: Identifiable, Equatable {
    let disc: ListeningDisc
    /// 歌曲结果打开唱片详情时定位到的曲目；唱片结果为 nil。
    let focusTrack: ListeningDiscTrack?

    var focusTrackID: String? { focusTrack?.id }
    var id: String { focusTrack.map { "track:\($0.id)" } ?? "disc:\(disc.id)" }
}

enum ListeningSearch {
    static func results(for query: String, in discs: [ListeningDisc]) -> (discs: [ListeningSearchResult], tracks: [ListeningSearchResult]) {
        guard !ArtistNameMatching.normalized(query).isEmpty else { return ([], []) }
        let matchedDiscs = discs
            .filter { disc in ([disc.title] + disc.artistNames).contains { ArtistNameMatching.contains($0, query: query) } }
            .map { ListeningSearchResult(disc: $0, focusTrack: nil) }
        var seenTracks = Set<String>()
        var matchedTracks: [ListeningSearchResult] = []
        // The same song can sit on a compilation and an album; rack order decides which disc opens.
        for disc in discs {
            for track in disc.tracks
            where ArtistNameMatching.contains(track.title, query: query) || ArtistNameMatching.contains(track.artistName, query: query) {
                guard seenTracks.insert(track.id).inserted else { continue }
                matchedTracks.append(ListeningSearchResult(disc: disc, focusTrack: track))
            }
        }
        return (matchedDiscs, matchedTracks)
    }
}
