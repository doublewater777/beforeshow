import Foundation

@MainActor extension ListeningRoomCoordinator {
    /// Starts a disc unless it is already the one playing, so a second tap never restarts it.
    func play(_ disc: ListeningDisc) {
        if !isOnDeckAndPlaying(disc) { loadPlayableDisc(disc) }
    }

    /// Warms a disc the user is about to reach: its artwork in the image cache and its songs in the player.
    func prefetch(_ disc: ListeningDisc) {
        if let url = disc.artworkURL {
            Task { _ = await ShowCoverImageCache.shared.image(from: url) }
        }
        guard let track = disc.tracks.first, let source = playbackSource(for: track) else { return }
        deck.prefetchUpcoming(disc, source: source)
    }

    /// Any disc on the deck counts, including artist releases outside the show's own shelf.
    func isOnDeckAndPlaying(_ disc: ListeningDisc) -> Bool {
        display.player.isPlaybackActive && loadedDisc?.id == disc.id
    }

    func pickCandidates(filter: ListeningDiscPickFilter) -> [ListeningDisc] {
        let candidates = ListeningDiscPickCandidates.discs(in: rackGroups, scope: .all)
            .filter { !$0.tracks.isEmpty && $0.origin == .album && filter.includes($0) }
        let loadable = candidates.filter { discPresentation(for: $0).canLoad }
        return loadable.isEmpty ? candidates : loadable
    }
}
