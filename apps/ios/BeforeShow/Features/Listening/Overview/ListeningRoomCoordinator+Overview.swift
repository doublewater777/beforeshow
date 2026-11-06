import Foundation

@MainActor extension ListeningRoomCoordinator {
    /// Starts a disc unless it is already the one playing, so a second tap never restarts it.
    func play(_ disc: ListeningDisc) {
        if !isOnDeckAndPlaying(disc) { loadPlayableDisc(disc) }
    }

    /// Any disc on the deck counts, including artist releases outside the show's own shelf.
    func isOnDeckAndPlaying(_ disc: ListeningDisc) -> Bool {
        display.player.isPlaybackActive && mechanism.hasDisc && mechanism.disc?.id == disc.id
    }

    func pickCandidates(filter: ListeningDiscPickFilter) -> [ListeningDisc] {
        let candidates = ListeningDiscPickCandidates.discs(in: rackGroups, scope: .all)
            .filter { !$0.tracks.isEmpty && $0.origin == .album && filter.includes($0) }
        let loadable = candidates.filter { discPresentation(for: $0).canLoad }
        return loadable.isEmpty ? candidates : loadable
    }
}
