import Foundation

/// An artist's releases played whole, in an order the listener can't predict: every record
/// once before any repeats, and a new round never opens with the record that just ended.
struct ListeningDiscShuffle: Equatable {
    let artistID: String
    private let pool: [ListeningDisc]
    private var remaining: [ListeningDisc]

    init?(artistID: String, discs: [ListeningDisc]) {
        let playable = discs.filter { !$0.tracks.isEmpty }
        guard !playable.isEmpty else { return nil }
        self.artistID = artistID
        pool = playable
        remaining = []
    }

    mutating func next<G: RandomNumberGenerator>(after last: ListeningDisc?, using generator: inout G) -> ListeningDisc {
        if remaining.isEmpty {
            remaining = pool.shuffled(using: &generator)
            if remaining.count > 1, remaining.last?.id == last?.id {
                remaining.swapAt(remaining.count - 1, 0)
            }
        }
        return remaining.removeLast()
    }

    mutating func next(after last: ListeningDisc?) -> ListeningDisc {
        var generator = SystemRandomNumberGenerator()
        return next(after: last, using: &generator)
    }

    /// What `next` will hand out, when the current round has it decided.
    var upcoming: ListeningDisc? { remaining.last }
}

extension ListeningRoomCoordinator {
    /// Starts an endless run through the artist's records; manual picks end it.
    func shuffleDiscography(of artistID: String, discs: [ListeningDisc]) {
        guard var run = ListeningDiscShuffle(artistID: artistID, discs: discs) else { return }
        let first = run.next(after: loadedDisc)
        loadPlayableDisc(first)
        shuffleRun = run
        if let upcoming = run.upcoming { prefetch(upcoming) }
    }

    func isShuffling(_ artistID: String) -> Bool { shuffleRun?.artistID == artistID && display.player.isPlaybackActive }

    /// When a shuffled record runs out on its own, the next one goes on.
    func advanceShuffle() {
        guard var run = shuffleRun else { return }
        let next = run.next(after: loadedDisc)
        loadPlayableDisc(next)
        shuffleRun = run
        if let upcoming = run.upcoming { prefetch(upcoming) }
    }
}
