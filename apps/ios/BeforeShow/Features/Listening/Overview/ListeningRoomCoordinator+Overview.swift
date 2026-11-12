import Foundation

enum ListeningPickCardState: Equatable {
    case ready, loading, failed, hidden
}

struct ListeningPickCatalogProgress: Equatable {
    let authorized: Bool
    let missing: [String]
    let statuses: [String: ListeningArtistCatalogStatus]
}

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

    func pickCandidates() -> [ListeningDisc] {
        let candidates = ListeningDiscPickCandidates.discs(in: rackGroups, scope: .all)
            .filter { !$0.tracks.isEmpty && $0.origin == .album }
        let loadable = candidates.filter { discPresentation(for: $0).canLoad }
        return loadable.isEmpty ? candidates : loadable
    }

    /// Lineup artists whose albums have not arrived, in shelf order. Albums come with an artist's full catalog,
    /// which otherwise loads only when the user opens that artist.
    var missingPickCatalogArtistIDs: [String] {
        let saved = Set(catalogSnapshots.map(\.artistID))
        return rackGroups.compactMap { group in
            guard case let .artist(id, _, isConnected) = group.kind, isConnected, !saved.contains(id) else { return nil }
            return id
        }
    }

    /// Changes whenever the next album list may start: one arriving or failing, access, the lineup.
    var pickCatalogProgress: ListeningPickCatalogProgress {
        ListeningPickCatalogProgress(authorized: access.authorizationStatus == .authorized,
                                     missing: missingPickCatalogArtistIDs, statuses: artistCatalogStatus)
    }

    /// One artist at a time, so a festival fills the shelf without a burst of requests; a failed artist waits for a retry.
    func loadNextPickCatalog() {
        let missing = missingPickCatalogArtistIDs
        guard !missing.contains(where: { artistCatalogStatus[$0] == .loading }),
              let next = missing.first(where: { artistCatalogStatus[$0] == nil }) else { return }
        loadArtistCatalogIfNeeded(next)
    }

    func retryPickCatalogs() {
        guard let failed = missingPickCatalogArtistIDs.first(where: { artistCatalogStatus[$0] == .failed }) else { return }
        loadArtistCatalogIfNeeded(failed)
    }

    var pickCardState: ListeningPickCardState {
        if !pickCandidates().isEmpty { return .ready }
        if catalogState == .loading { return .loading }
        let statuses = missingPickCatalogArtistIDs.map { artistCatalogStatus[$0] }
        if statuses.contains(where: { $0 != .failed }) {
            return access.authorizationStatus == .authorized ? .loading : .hidden
        }
        return statuses.isEmpty ? .hidden : .failed
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

        let candidates = pickCandidates()
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
