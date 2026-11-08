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

    /// Stages a default track from the show's pick pool or daily featured disc
    /// so the resident mini player is never empty when songs are available.
    /// Does not start playback (paused, ready for user tap).
    @discardableResult
    func stageDefaultTrackIfNeeded(
        songPicker: ([ListeningDiscTrack]) -> ListeningDiscTrack? = { $0.randomElement() ?? $0.first }
    ) -> ListeningDiscTrack? {
        guard !hasLoadedDisc || track == nil else { return track }
        guard let show else { return nil }

        let candidates = pickCandidates(filter: .all)
        let pool = (candidates.isEmpty ? discs : candidates).filter { !$0.tracks.isEmpty }
        guard !pool.isEmpty else { return nil }

        let chosenDisc: ListeningDisc?
        if let pick = ListeningDiscPickPolicy.pick(
            showID: show.id,
            scopeKey: ListeningDiscPickPolicy.showScopeKey,
            candidates: pool,
            lineupNames: show.artistNames
        ), !pick.tracks.isEmpty {
            chosenDisc = pick
        } else if let today = todayDisc(), !today.tracks.isEmpty {
            chosenDisc = today
        } else {
            chosenDisc = pool.first
        }

        guard let disc = chosenDisc, !disc.tracks.isEmpty else { return nil }
        guard let song = songPicker(disc.tracks) ?? disc.tracks.first else { return nil }

        loadDisc(disc, songID: song.id, autoplay: false)
        if ListeningRoomSessionStore.shared.room === self {
            ListeningRoomSessionStore.shared.publishChrome(self)
        }
        return song
    }
}
