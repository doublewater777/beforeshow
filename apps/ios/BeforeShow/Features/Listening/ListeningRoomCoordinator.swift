import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct ListeningFullCatalogFetch: Sendable {
    let artistID: String
    let payload: ListeningArtistCatalogPayload?
    let failed: Bool
}

private let listeningCatalogFetchConcurrency = 4

@MainActor @Observable final class ListeningRoomCoordinator {
    enum CatalogState { case loading, ready, unmatched, cacheFailed, unavailable }

    #if DEBUG
    /// When set (simulator previews), lid-open gestures reveal the disc
    /// instead of stopping playback.
    var opensWithoutStopping = false
    #endif

    let mechanism = CDMechanism()
    /// The CD player's transport: what is loaded, and the Apple player that plays it.
    let deck: ListeningDeck
    private(set) var catalogSongs: [CatalogSong] = []
    private(set) var catalogAlbums: [CatalogAlbum] = []
    private(set) var openingTiers: [ShowOpeningArtistTier] = []
    private(set) var catalogSnapshots: [ArtistCatalogSnapshot] = []
    private(set) var show: Show?
    private(set) var discs: [ListeningDisc] = []

    #if DEBUG
    /// Test hook: put a disc straight into the tray without touching the
    /// catalog pipeline (used by `--listen-seed-disc` for simulator previews).
    func seedDisc(_ disc: ListeningDisc) {
        if !discs.contains(disc) { discs.append(disc) }
        mechanism.restoreSeated(disc)
        mechanism.setLid(open: true)
        opensWithoutStopping = true
        deck.load([disc], cursor: disc.tracks.first?.id)
    }
    #endif
    private(set) var catalogState: CatalogState = .loading
    private(set) var access = ListeningMusicAccess(authorizationStatus: .notDetermined, canPlayCatalogContent: false)
    private(set) var isAuthorizing = false
    private(set) var isCatalogEnriching = false
    var isPlaying: Bool { deck.isPlaying }
    var wantsPlayback: Bool { deck.wantsPlayback }
    var playPauseAction: ListeningPlayPauseAction { display.player.playPauseAction }
    private(set) var wantedSongIDs: Set<String> = []
    private(set) var familiarSongIDs: Set<String> = []
    private(set) var actualSongIDs: Set<String> = []
    private(set) var recentListening: ShowRecentListening?
    @ObservationIgnored private var recordedPlayingSongID: String?
    private(set) var excludedArtistIDs: Set<String> = []
    var onlyArtistID: String? {
        guard case let .artist(id) = browser.scope else { return nil }
        return id
    }
    var browser = ListeningBrowseState()
    private(set) var browseArtists: [ListeningBrowseArtist] = []
    private(set) var compilationDiscs: [ListeningDisc] = []
    /// A mechanical sequence (disc swap, closing the lid to play) is running.
    private(set) var busy = false
    var errorText: String?
    var playbackError: String?
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var musicAccessRequestGeneration = UUID()
    private(set) var accessResolved = false
    @ObservationIgnored private var runtimeSongs: [String: [CatalogSong]] = [:]
    var presentation: ListeningPresentation {
        .resolve(hasShow: show != nil, authorized: access.authorizationStatus == .authorized,
                 connected: show?.artists.contains { $0.appleMusicArtistID != nil } == true,
                 hasSongs: !discs.isEmpty, loading: catalogState == .loading,
                 failed: catalogState == .cacheFailed, accessResolved: accessResolved)
    }
    func wantedPresentation(_ id: String) -> ListeningWantsLivePresentation {
        .init(selected: wantedSongIDs.contains(id), mutable: show.map { WantsLivePolicy.isMutable(show: $0) } ?? false)
    }
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let catalogService: any ListeningMusicCatalogServicing
    @ObservationIgnored private let artistSearchService: any ArtistSearchServicing
    @ObservationIgnored private let catalogStore: ListeningCatalogStore
    @ObservationIgnored private let evidenceCoordinatorFactory: @MainActor (ModelContext) throws -> ListeningPlaybackEvidenceCoordinator
    @ObservationIgnored private var playbackEvidenceCoordinator: ListeningPlaybackEvidenceCoordinator?
    @ObservationIgnored private var evidenceRetryTask: Task<Void, Never>?
    @ObservationIgnored private var evidenceRetryPending = false
    @ObservationIgnored private var evidenceFailureAlertShown = false
    @ObservationIgnored private var evidenceFailureOwnsErrorText = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var widgetCoverTask: Task<Void, Never>?
    @ObservationIgnored private var catalogGeneration = UUID()
    @ObservationIgnored private var showCatalogKey: String?
    @ObservationIgnored private var completedCatalogKey: String?
    @ObservationIgnored private var catalogProjectionContext: ModelContext?
    @ObservationIgnored private var featuredPlaylistTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var loadedFeaturedPlaylistArtistIDs: Set<String> = []
    private(set) var initialLoaded = false
    @ObservationIgnored private var isLoadingShow = false
    @ObservationIgnored private var active = true

    init(context: ModelContext, catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
         artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
         playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
             $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
         },
         evidenceCoordinatorFactory: @escaping @MainActor (ModelContext) throws -> ListeningPlaybackEvidenceCoordinator = {
             try ListeningPlaybackEvidenceCoordinator(modelContext: $0)
         }) {
        self.context = context; self.catalogService = catalogService
        self.artistSearchService = artistSearchService
        self.evidenceCoordinatorFactory = evidenceCoordinatorFactory
        catalogStore = ListeningCatalogStore(modelContext: context, service: catalogService)
        deck = ListeningDeck(makeEngine: playbackFactory)
        deck.evidenceProvider = { [weak self] in try? self?.playbackEvidenceCoordinatorForUse() }
        deck.onCursorChange = { [weak self] _ in self?.deckCursorDidChange() }
        deck.onTransportChange = { [weak self] in self?.deckTransportDidChange() }
        deck.onProgress = { [weak self] time in self?.deckDidProgress(time) }
        deck.onEvidence = { [weak self] result, immediate in
            self?.applyDeckEvidence(result, representDismissedAlert: immediate)
        }
        deck.onFailure = { [weak self] in self?.playbackError = BSLocalization.text("暂时无法播放") }
        mechanism.onOpen = { [weak self] in
            #if DEBUG
            if self?.opensWithoutStopping == true { return }
            #endif
            self?.lidDidOpen()
        }
        mechanism.onTransition = { [weak self] transition in
            CDSoundPlayer.shared.play(transition)
            self?.handleMechanismTransition(transition)
            #if os(iOS)
            switch transition {
            case "seat", "close":
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "open", "pickup":
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "blocked":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default:
                break
            }
            #endif
        }
        restorePersistedDiscIfNeeded()
    }

    /// Opening the lid stops the motor; the track and its position stay loaded.
    private func lidDidOpen() {
        deck.pause()
        persistLoadedDisc(force: true)
    }

    private func handleMechanismTransition(_ transition: String) {
        switch transition {
        case "seat":
            // Automatic swaps load the deck themselves once the tray settles.
            guard !mechanism.isAutomatic, let disc = mechanism.disc else { return }
            deck.load(queueDiscs(for: disc), cursor: discPresentation(for: disc).defaultPlayableTrackID)
            persistLoadedDisc(force: true)
            finalizeManualDiscInsertionIfNeeded()
        case "remove":
            deck.eject()
            if !mechanism.isAutomatic { clearPersistedDisc() }
            syncWidgetListeningState()
        case "store":
            deck.eject()
            clearPersistedDisc()
            syncWidgetListeningState()
        default:
            break
        }
    }

    private func deckCursorDidChange() {
        // A compilation shows the volume that holds the current song.
        if let volume = deck.currentDisc, let seated = mechanism.disc, volume.id != seated.id {
            mechanism.updateContents(volume)
        }
        recordedPlayingSongID = nil
        recordPlayingIfNeeded()
        persistLoadedDisc(force: true)
    }

    private func deckTransportDidChange() {
        recordPlayingIfNeeded()
        if !deck.wantsPlayback {
            persistLoadedDisc(force: true)
        }
        syncWidgetListeningState()
    }

    private func deckDidProgress(_ time: TimeInterval) {
        persistLoadedDisc(currentTime: time)
        if active, foreground, time > 0 {
            AppReviewPrompt.consider(.listenedToSong)
        }
    }

    private func restorePersistedDiscIfNeeded() {
        guard mechanism.position == .stored else { return }
        do {
            let states = try context.fetch(FetchDescriptor<ListeningLoadedDiscState>())
            guard let state = states.max(by: { $0.updatedAt < $1.updatedAt }) else { return }
            guard let disc = try? JSONDecoder().decode(ListeningDisc.self, from: state.discData), !disc.tracks.isEmpty else {
                for state in states { context.delete(state) }
                try context.save()
                return
            }
            let songID = state.songID.flatMap { id in disc.tracks.contains { $0.id == id } ? id : nil }
            mechanism.restoreSeated(disc)
            deck.load([disc], cursor: songID, resumeAt: songID == nil ? 0 : state.currentTime ?? 0)
        } catch {}
    }
    private func persistLoadedDisc(currentTime: TimeInterval? = nil, force: Bool = false) {
        guard mechanism.position == .seated, let disc = mechanism.disc else { return }
        do {
            let songID = deck.cursorSongID.flatMap { id in disc.tracks.contains { $0.id == id } ? id : nil }
            let time = currentTime ?? deck.time
            guard time.isFinite, time >= 0 else { return }
            let states = try context.fetch(FetchDescriptor<ListeningLoadedDiscState>())
            if let state = states.first {
                if !force, state.songID == songID, abs((state.currentTime ?? 0) - time) < 5 { return }
                let data = try JSONEncoder().encode(disc)
                state.discData = data
                state.songID = songID
                state.currentTime = time
                state.updatedAt = Date()
                for duplicate in states.dropFirst() { context.delete(duplicate) }
            } else {
                let data = try JSONEncoder().encode(disc)
                context.insert(ListeningLoadedDiscState(discData: data, songID: songID, currentTime: time))
            }
            try context.save()
            syncWidgetListeningState()
        } catch {}
    }
    private func clearPersistedDisc() {
        do {
            for state in try context.fetch(FetchDescriptor<ListeningLoadedDiscState>()) {
                context.delete(state)
            }
            try context.save()
        } catch {}
    }
    func discardLoadedDiscState() {
        operation?.cancel()
        operation = nil
        deck.eject()
        mechanism.discardDisc()
        clearPersistedDisc()
        syncWidgetListeningState()
    }
    /// 未装碟时小组件播放键会装入的唱片
    var defaultDisc: ListeningDisc? {
        compilationDiscs.first ?? discs.first
    }
    /// - Parameter isPlayingOverride: Optional widget-local command projection.
    func syncWidgetListeningState(isPlayingOverride: Bool? = nil) {
        // 未装碟时展示播放键将要装入的唱片；封面只用唱片封面，现场海报留给倒计时小组件
        let disc = mechanism.disc ?? defaultDisc
        let currentTrack = track
        let artist = currentTrack?.artistName ?? disc?.artistNames.first
        let artwork = currentTrack?.artworkURL?.absoluteString ?? disc?.artworkURL?.absoluteString
        let snapshot = WidgetListeningSnapshot(
            showID: show?.id,
            showName: show?.name ?? (WidgetSnapshotStore.read()?.name ?? ""),
            artistName: artist,
            discTitle: disc?.title,
            trackTitle: currentTrack?.title,
            coverImageURL: artwork,
            trackCount: disc?.tracks.count,
            isPlaying: isPlayingOverride ?? wantsPlayback,
            generatedAt: Date()
        )
        let previous = WidgetListeningStore.read()
        if previous == nil || !previous!.isContentEqual(to: snapshot) {
            WidgetListeningStore.write(snapshot)
            BeforeShowWidgetKind.reloadAllTimelines()
        }
        prefetchWidgetCover(artwork)
    }
    /// 小组件扩展的后台刷新受系统预算限制，封面由 App 下载进 App Group 后再刷新小组件。
    private func prefetchWidgetCover(_ source: String?) {
        guard let source, WidgetCoverCache.cachedCoverPath(matching: source) == nil else { return }
        widgetCoverTask?.cancel()
        widgetCoverTask = Task {
            await WidgetCoverCache.refresh(for: source)
            guard !Task.isCancelled, WidgetCoverCache.cachedCoverPath(matching: source) != nil else { return }
            BeforeShowWidgetKind.reloadAllTimelines()
        }
    }
    var track: ListeningDiscTrack? {
        guard mechanism.position != .stored, mechanism.disc != nil else { return nil }
        return deck.currentTrack
    }

    /// Position of the current track on the visible record.
    var trackIndex: Int {
        guard let disc = mechanism.disc, let songID = deck.cursorSongID else { return 0 }
        return disc.tracks.firstIndex { $0.id == songID } ?? 0
    }

    var playerDisplayTrack: ListeningDiscTrack? { track }

    var playerDisplayTrackIndex: Int? {
        guard let disc = mechanism.disc, let track else { return nil }
        return disc.tracks.firstIndex { $0.id == track.id }
    }

    var isPlayerDisplayPreparing: Bool { deck.phase == .preparing }

    var playerDisplayTimeText: String {
        isPlayerDisplayPreparing ? "00:00" : timeText
    }

    var elapsed: TimeInterval {
        deck.phase == .finished ? deck.duration ?? deck.time : deck.time
    }

    var timeText: String {
        let time = elapsed.isFinite ? Int(max(0, min(elapsed, 86400))) : 0
        return String(format: "%02d:%02d", time / 60, time % 60)
    }
    func capability(for track: ListeningDiscTrack?) -> ListeningMusicCapability {
        ListeningMusicCapabilityResolver.resolve(access: access, hasPreviewAsset: track?.previewURL != nil, hasCatalogMetadata: track != nil)
    }

    /// The source a song would play from now. An established full-catalog
    /// session keeps serving its queue while access cannot be re-confirmed.
    func playbackSource(for track: ListeningDiscTrack) -> ListeningPlaybackSource? {
        let established = deck.isFinished || !deck.tracks.contains(where: { $0.id == track.id })
            ? nil : deck.source
        return ListeningPlaybackSourceResolver.resolve(
            capability: capability(for: track),
            access: access,
            establishedSource: established
        )
    }
    var capabilityTitle: String {
        switch capability(for: track) {
        case .fullPlayback: BSLocalization.text("完整播放")
        case .previewOnly: BSLocalization.text("30 秒试听")
        case .metadataOnly: BSLocalization.text("仅歌曲信息")
        case .unavailable: BSLocalization.text("暂不可播放")
        }
    }
    func catalogKey(for show: Show) -> String {
        show.id.uuidString + show.artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
    }
    func shouldReloadCatalog(for show: Show) -> Bool {
        let key = catalogKey(for: show)
        if self.show?.id != show.id || showCatalogKey != key { return true }
        if isLoadingShow || isCatalogEnriching { return false }
        return completedCatalogKey != key
    }

    /// Prepare the fixed room and persisted records without requesting music access
    /// or artist/catalog enrichment. The inactive root uses this before first entry.
    func prepareForDisplay(show: Show) {
        let newKey = catalogKey(for: show)
        if self.show?.id != show.id {
            // Visible failures belong to the room the user just left. Retry work,
            // including playback-evidence persistence, continues independently.
            errorText = nil
            playbackError = nil
            cancelFeaturedPlaylistTasks(clearLoaded: true)
            initialLoaded = false
            browser = ListeningBrowseState()
            recentListening = nil
        }
        if showCatalogKey != newKey {
            cancelFeaturedPlaylistTasks(clearLoaded: true)
            completedCatalogKey = nil
            discs = []; runtimeSongs = [:]
        }
        showCatalogKey = newKey
        self.show = show
        catalogState = .loading

        let knownStatus = catalogService.currentAuthorizationStatus()
        if access.authorizationStatus != knownStatus || !accessResolved {
            access = ListeningMusicAccess(authorizationStatus: knownStatus, canPlayCatalogContent: false)
            accessResolved = knownStatus != .authorized
        }
        do {
            try rebuildDiscs()
        } catch {
            catalogState = .cacheFailed
        }

        // `initialLoaded` means the fixed room and any cached records are ready to
        // present. It deliberately does not wait for artist lookup or catalog IO.
        initialLoaded = true
    }

    func load(show: Show, force: Bool = false) async {
        let generation = UUID()
        catalogGeneration = generation
        isLoadingShow = true
        defer {
            if generation == catalogGeneration {
                isLoadingShow = false
                // 目录到齐后未装碟时的默认唱片可能变化
                syncWidgetListeningState()
                prewarmLoadedDisc()
                if case let .artist(artistID) = browser.scope {
                    scheduleSelectedArtistCatalogLoadIfNeeded(for: artistID)
                }
            }
        }

        prepareForDisplay(show: show)
        syncWidgetListeningState()

        // Subscription lookup and artist identity lookup are independent. Publish
        // resolved access immediately so cached records can play during matching.
        let initialSlots = show.artists
        let reusableMatches = reusableArtistMatches(for: initialSlots)
        applyAutomaticArtistMatches(reusableMatches, originalSlots: initialSlots, to: show)

        let slots = show.artists
        async let matching = ArtistIdentityMatcher(search: artistSearchService).matches(for: slots)
        let accessGeneration = beginMusicAccessRequest()
        let newAccess = await catalogService.currentAccess()
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        if isCurrentMusicAccessRequest(accessGeneration) {
            access = newAccess
            accessResolved = true
        }

        let matches = (try? await matching) ?? [:]
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        applyAutomaticArtistMatches(matches, originalSlots: slots, to: show)
        guard generation == catalogGeneration, !Task.isCancelled else { return }

        if let completedKey = await loadCatalogUntilIdentityStable(generation: generation, force: force) {
            completedCatalogKey = completedKey
        }
    }

    private func reusableArtistMatches(for slots: [ArtistSlot]) -> [Int: RecognizedArtist] {
        let unresolved = slots.enumerated().filter {
            $0.element.appleMusicArtistID == nil
                && AppleMusicArtistIdentity.artistID(from: $0.element.appleMusicURL) == nil
        }
        guard !unresolved.isEmpty,
              let shows = try? context.fetch(FetchDescriptor<Show>()) else {
            return [:]
        }

        var knownByName: [String: [String: ArtistSlot]] = [:]
        for source in shows.flatMap(\.artists) {
            guard let rawID = source.appleMusicArtistID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawID.isEmpty else { continue }
            let key = ArtistNameMatching.normalized(source.name)
            guard !key.isEmpty else { continue }

            var identities = knownByName[key, default: [:]]
            if var existing = identities[rawID] {
                if existing.appleMusicURL == nil { existing.appleMusicURL = source.appleMusicURL }
                if existing.avatarURL == nil { existing.avatarURL = source.avatarURL }
                identities[rawID] = existing
            } else {
                identities[rawID] = source
            }
            knownByName[key] = identities
        }

        var result: [Int: RecognizedArtist] = [:]
        for (index, slot) in unresolved {
            let key = ArtistNameMatching.normalized(slot.name)
            guard !key.isEmpty,
                  let identities = knownByName[key],
                  identities.count == 1,
                  let (artistID, source) = identities.first else { continue }

            result[index] = RecognizedArtist(
                id: artistID,
                canonicalName: source.name,
                avatarURL: source.avatarURL.flatMap(URL.init(string:)),
                appleMusicURL: source.appleMusicURL.flatMap(URL.init(string:))
            )
        }
        return result
    }

    private func applyAutomaticArtistMatches(
        _ matches: [Int: RecognizedArtist],
        originalSlots slots: [ArtistSlot],
        to show: Show
    ) {
        guard !matches.isEmpty else { return }
        do {
            var artists = show.artists
            var changed = false
            for (index, candidate) in matches {
                guard artists.indices.contains(index), slots.indices.contains(index),
                      artists[index].name == slots[index].name,
                      artists[index].appleMusicArtistID == nil else { continue }
                artists[index].appleMusicArtistID = candidate.id
                artists[index].appleMusicURL = candidate.appleMusicURL?.absoluteString
                if artists[index].avatarURL == nil { artists[index].avatarURL = candidate.avatarURL?.absoluteString }
                changed = true
            }
            guard changed else { return }
            show.artists = artists
            show.updatedAt = Date()
            _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context)
            try context.save()
            showCatalogKey = catalogKey(for: show)
            try rebuildDiscs()
        } catch {
            context.rollback()
        }
    }

    /// Refresh only the music payload for the already-bound show. Authorization and
    /// retry paths use this instead of restarting artist matching and room setup.
    func reloadCatalog(force: Bool = false) async {
        guard show != nil, !isLoadingShow else { return }
        let startingScope = browser.scope
        let generation = UUID()
        catalogGeneration = generation
        catalogState = .loading
        defer {
            if generation == catalogGeneration,
               startingScope != browser.scope,
               case let .artist(artistID) = browser.scope {
                scheduleSelectedArtistCatalogLoadIfNeeded(for: artistID)
            }
        }
        if let completedKey = await loadCatalogUntilIdentityStable(generation: generation, force: force) {
            initialLoaded = true
            completedCatalogKey = completedKey
        }
    }

    /// A catalog pass snapshots the artist IDs at its start. Identity can still change
    /// while that network work is suspended, so only mark the exact key that the pass
    /// actually covered as complete. If it drifted, repeat just the catalog stage with
    /// the same generation; artist matching and room setup are never repeated.
    private func loadCatalogUntilIdentityStable(generation: UUID, force: Bool) async -> String? {
        guard let show else { return nil }
        while generation == catalogGeneration, !Task.isCancelled {
            let startedKey = catalogKey(for: show)
            showCatalogKey = startedKey
            await loadCatalog(generation: generation, force: force)
            guard generation == catalogGeneration, !Task.isCancelled else { return nil }

            let latestKey = catalogKey(for: show)
            showCatalogKey = latestKey
            guard latestKey != startedKey else { return startedKey }

            // A rematch landed after this pass captured its artist IDs. Keep the new
            // identity pending and immediately run one catalog-only pass for it.
            completedCatalogKey = nil
            catalogState = .loading
        }
        return nil
    }

    private func loadCatalog(generation: UUID, force: Bool) async {
        guard let show else { return }
        let ids = show.artists.compactMap(\.appleMusicArtistID).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        guard !ids.isEmpty else {
            discs = []
            catalogState = .unmatched
            return
        }

        guard access.authorizationStatus == .authorized else {
            catalogState = discs.isEmpty ? .unavailable : .ready
            return
        }

        isCatalogEnriching = true
        defer {
            if generation == catalogGeneration { isCatalogEnriching = false }
        }

        var failedIDs = Set<String>()
        let snapshotsByID = Dictionary(
            catalogSnapshots.map { ($0.artistID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let now = Date()
        let quickIDs = ids.filter { artistID in
            guard force || runtimeSongs[artistID] == nil else { return false }
            guard let snapshot = snapshotsByID[artistID] else { return true }
            return force || ListeningCatalogRefreshPolicy.shouldRefresh(
                fetchedAt: snapshot.fetchedAt,
                now: now
            )
        }

        // Publish the first playable songs as soon as they arrive. Subsequent
        // results are coalesced to avoid rebuilding SwiftData projections per song.
        var received = 0
        await ListeningRuntimeCatalogLoader.fetch(artistIDs: quickIDs, service: catalogService) { result in
            guard generation == self.catalogGeneration, !Task.isCancelled else { return }
            received += 1
            if result.failed {
                failedIDs.insert(result.artistID)
            } else {
                self.runtimeSongs[result.artistID] = result.songs.map {
                    CatalogSong(
                        appleMusicSongID: $0.songID,
                        title: $0.title,
                        artistName: $0.artistName,
                        artworkURL: $0.artworkURL,
                        duration: $0.duration,
                        performerArtistIDs: $0.performerArtistIDs,
                        previewURL: $0.previewURL
                    )
                }
            }
            guard (self.discs.isEmpty && !result.songs.isEmpty)
                    || received.isMultiple(of: listeningCatalogFetchConcurrency)
                    || received == quickIDs.count else { return }
            do {
                try self.rebuildDiscs()
                if !self.discs.isEmpty { self.catalogState = .ready }
            } catch {
                self.catalogState = .cacheFailed
            }
        }

        guard generation == catalogGeneration, !Task.isCancelled else { return }

        // Runtime top songs are sufficient for the all-artists compilation scope.
        // Full artist catalogs are browse/familiarity data and are loaded only for
        // the artist the user explicitly selects.
        let fullIDs: [String]
        if case let .artist(selectedID) = browser.scope, ids.contains(selectedID) {
            let needsRefresh: Bool
            if force {
                needsRefresh = true
            } else if let snapshot = snapshotsByID[selectedID] {
                needsRefresh = ListeningCatalogRefreshPolicy.shouldRefresh(
                    fetchedAt: snapshot.fetchedAt,
                    now: now
                )
            } else {
                needsRefresh = true
            }
            fullIDs = needsRefresh ? [selectedID] : []
        } else {
            fullIDs = []
        }
        if !fullIDs.isEmpty {
            _ = await fetchFullCatalog(for: fullIDs) { [weak self] batchValues in
                guard let self, generation == self.catalogGeneration, !Task.isCancelled else { return }
                var batchPayloads: [ListeningArtistCatalogPayload] = []
                for result in batchValues {
                    if let payload = result.payload, !result.failed {
                        batchPayloads.append(payload)
                    } else {
                        failedIDs.insert(result.artistID)
                    }
                }
                if !batchPayloads.isEmpty {
                    do {
                        let persistedIDs = try await self.catalogStore.persistArtistCatalogBatch(batchPayloads)
                        failedIDs.subtract(persistedIDs)
                        for artistID in persistedIDs {
                            self.runtimeSongs.removeValue(forKey: artistID)
                        }
                    } catch {
                        failedIDs.formUnion(batchPayloads.map(\.artistID))
                    }
                    guard generation == self.catalogGeneration, !Task.isCancelled else { return }
                    try? self.rebuildDiscs()
                    if !self.discs.isEmpty { self.catalogState = .ready }
                }
            }
            guard generation == catalogGeneration, !Task.isCancelled else { return }
        }

        do {
            try rebuildDiscs()
            catalogState = failedIDs.isEmpty ? (discs.isEmpty ? .unavailable : .ready) : .cacheFailed
            if case let .artist(artistID) = browser.scope {
                loadFeaturedPlaylistsIfNeeded(for: artistID)
            }
        } catch {
            catalogState = .cacheFailed
        }
    }

    private func fetchFullCatalog(
        for artistIDs: [String],
        onBatchPersisted: (([ListeningFullCatalogFetch]) async -> Void)? = nil
    ) async -> [ListeningFullCatalogFetch] {
        let service = catalogService
        let fetchedAt = Date()
        var results: [ListeningFullCatalogFetch] = []
        var cursor = 0
        while cursor < artistIDs.count, !Task.isCancelled {
            let end = min(cursor + listeningCatalogFetchConcurrency, artistIDs.count)
            let batch = Array(artistIDs[cursor..<end])
            let values = await withTaskGroup(
                of: ListeningFullCatalogFetch.self,
                returning: [ListeningFullCatalogFetch].self
            ) { group in
                for artistID in batch {
                    group.addTask {
                        do {
                            let payload = try await service.fetchArtistCatalog(
                                artistID: artistID,
                                fetchedAt: fetchedAt
                            )
                            return ListeningFullCatalogFetch(artistID: artistID, payload: payload, failed: false)
                        } catch {
                            return ListeningFullCatalogFetch(artistID: artistID, payload: nil, failed: true)
                        }
                    }
                }
                var batchResults: [ListeningFullCatalogFetch] = []
                for await value in group { batchResults.append(value) }
                return batchResults
            }
            results.append(contentsOf: values)
            if let onBatchPersisted {
                await onBatchPersisted(values)
            }
            cursor = end
        }
        return results
    }

    private func beginMusicAccessRequest() -> UUID {
        let generation = UUID()
        musicAccessRequestGeneration = generation
        return generation
    }

    private func isCurrentMusicAccessRequest(_ generation: UUID) -> Bool {
        generation == musicAccessRequestGeneration
    }

    func authorize() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        _ = await catalogService.requestAuthorization()
        let accessGeneration = beginMusicAccessRequest()
        let newAccess = await catalogService.currentAccess()
        guard isCurrentMusicAccessRequest(accessGeneration) else {
            isAuthorizing = false
            return
        }
        endFullPlaybackSessionForCapabilityLossIfNeeded(newAccess)
        access = newAccess
        accessResolved = true
        isAuthorizing = false

        guard newAccess.authorizationStatus == .authorized else { return }
        await matchUnconnectedArtistsAfterAuthorization()
        // If initial show preparation is still matching identities, that operation
        // will continue into catalog loading with the newly-authorized access.
        guard !isLoadingShow else { return }
        await reloadCatalog()
    }

    private func matchUnconnectedArtistsAfterAuthorization() async {
        guard let show else { return }
        let slots = show.artists
        let matches = (try? await ArtistIdentityMatcher(search: artistSearchService).matches(for: slots)) ?? [:]
        guard self.show?.id == show.id else { return }
        applyAutomaticArtistMatches(matches, originalSlots: slots, to: show)
    }

    func refreshMusicAccess() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        let accessGeneration = beginMusicAccessRequest()
        let newAccess = await catalogService.currentAccess()
        guard isCurrentMusicAccessRequest(accessGeneration) else {
            isAuthorizing = false
            return
        }
        access = newAccess
        accessResolved = true
        isAuthorizing = false

        guard newAccess.authorizationStatus == .authorized else { return }
        guard !isLoadingShow else { return }
        await reloadCatalog()
    }

    /// Returning from Settings is an authorization boundary, not just a transport
    /// lifecycle event. Refresh silently so a permission or subscription change is
    /// reflected without showing the transient connecting state on every foreground.
    func refreshMusicAccessAfterForeground() async {
        guard !isAuthorizing else { return }
        let previousAccess = access
        let accessGeneration = beginMusicAccessRequest()
        let newAccess = await catalogService.currentAccess()
        guard isCurrentMusicAccessRequest(accessGeneration) else { return }

        // Resolution belongs to the winning request, even when the resolved value
        // matches the provisional authorized/account-limited state published by load.
        // Otherwise a superseded initial load can leave the room connecting forever.
        accessResolved = true
        guard newAccess != previousAccess else { return }

        endFullPlaybackSessionForCapabilityLossIfNeeded(newAccess)
        access = newAccess

        guard !isLoadingShow else { return }
        let authorizationChanged = previousAccess.authorizationStatus != newAccess.authorizationStatus
        let playbackAccessChanged = previousAccess.catalogPlaybackAccess != newAccess.catalogPlaybackAccess
        guard authorizationChanged || playbackAccessChanged else { return }

        await reloadCatalog(
            force: authorizationChanged && newAccess.authorizationStatus == .authorized
        )
    }

    private func rebuildDiscs() throws {
        guard let show else { return }
        excludedArtistIDs = Set(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>())
            .filter { $0.showID == show.id && $0.isExcluded }.map(\.artistID))

        // A fresh read context observes background actor saves immediately without
        // passing managed objects across actor boundaries.
        let projectionContext = ModelContext(context.container)
        catalogProjectionContext = projectionContext
        catalogSongs = try projectionContext.fetch(FetchDescriptor<CatalogSong>())
        let cachedIDs = Set(catalogSongs.map(\.appleMusicSongID))
        catalogSongs += runtimeSongs.values.flatMap { $0 }.filter { !cachedIDs.contains($0.appleMusicSongID) }
        catalogAlbums = try projectionContext.fetch(FetchDescriptor<CatalogAlbum>())
        openingTiers = try projectionContext.fetch(FetchDescriptor<ShowOpeningArtistTier>()).filter { $0.showID == show.id }
        catalogSnapshots = try projectionContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        loadedFeaturedPlaylistArtistIDs.formUnion(
            catalogSnapshots.filter { !$0.featuredPlaylists.isEmpty }.map(\.artistID)
        )

        let songsByID = Dictionary(catalogSongs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { a, _ in a })
        let albumsByID = Dictionary(catalogAlbums.map { ($0.appleMusicAlbumID, $0) }, uniquingKeysWith: { a, _ in a })
        let mappedArtists: [ListeningBrowseArtist] = show.artists.enumerated().map { index, slot in
            if let id = slot.appleMusicArtistID {
                let snapshot = catalogSnapshots.first { $0.artistID == id }
                let albums = (snapshot?.albumIDs ?? []).compactMap { albumsByID[$0] }
                let featuredPlaylists = ListeningDiscAssembler.discs(
                    featuredPlaylists: snapshot?.featuredPlaylists ?? [],
                    artistID: id,
                    songsByID: songsByID
                )
                let releases = ListeningDiscAssembler.discs(albums: albums, songsByID: songsByID)
                return ListeningBrowseArtist(
                    slotIndex: index,
                    id: id,
                    name: slot.name,
                    artworkURL: (slot.avatarURL ?? snapshot?.artworkURL).flatMap(URL.init(string:)),
                    appleMusicArtistID: id,
                    albums: featuredPlaylists + releases
                )
            } else {
                return ListeningBrowseArtist(
                    slotIndex: index,
                    id: "unconnected-\(index)",
                    name: slot.name,
                    artworkURL: slot.avatarURL.flatMap(URL.init(string:)),
                    appleMusicArtistID: nil,
                    albums: []
                )
            }
        }
        let connected = mappedArtists.filter(\.isConnected)
        let unconnected = mappedArtists.filter { !$0.isConnected }
        browseArtists = connected + unconnected
        compilationDiscs = ListeningCompilationAssembler.discs(showID: show.id, artistTracks: browseArtists.compactMap { artist in
            guard let id = artist.appleMusicArtistID else {
                return nil
            }
            if let runtime = runtimeSongs[id], !runtime.isEmpty {
                return runtime.map(ListeningDiscTrack.init)
            }
            if let snapshot = catalogSnapshots.first(where: { $0.artistID == id }) {
                return snapshot.topSongIDs.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
            }
            return []
        })
        var discIDs = Set<String>()
        discs = (compilationDiscs + browseArtists.flatMap(\.albums)).filter { discIDs.insert($0.id).inserted }
        let validArtistIDs = Set(browseArtists.map(\.id))
        browser.reconcile(validArtistIDs: validArtistIDs)
        try refreshEvidence()
        recentListening = try context.fetch(FetchDescriptor<ShowRecentListening>()).first { $0.showID == show.id }
    }
    private func refreshEvidence() throws {
        guard let show else { return }
        wantedSongIDs = Set(try context.fetch(FetchDescriptor<ShowWantsLiveSong>()).filter { $0.showID == show.id }.map(\.songID))
        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        familiarSongIDs = FamiliarityEvidenceResolver.familiarSongIDs(
            records: records,
            setlistMemories: try context.fetch(FetchDescriptor<ShowSetlistMemory>()))
        actualSongIDs = Set(records.compactMap {
            $0.actualListeningAt == nil ? nil : $0.songID
        })
    }
    func containsHeardSongs(_ disc: ListeningDisc) -> Bool {
        disc.tracks.contains { actualSongIDs.contains($0.id) }
    }
    func isRecentDisc(_ disc: ListeningDisc) -> Bool {
        guard let recentListening, recentListening.showID == show?.id,
              recentListening.discID == disc.id else { return false }
        return disc.tracks.contains { $0.id == recentListening.songID }
    }
    private func recordPlayingIfNeeded() {
        guard deck.isPlaying, let show, let track, let disc = mechanism.disc,
              recordedPlayingSongID != track.id else { return }
        do {
            let record = recentListening ?? ShowRecentListening(showID: show.id, discID: disc.id, songID: track.id)
            if recentListening == nil { context.insert(record) }
            record.discID = disc.id
            record.songID = track.id
            record.playedAt = Date()
            try context.save()
            recentListening = record
            recordedPlayingSongID = track.id
        } catch { errorText = BSLocalization.text("保存失败，请重试") }
    }
    func toggleWanted(_ songID: String) {
        guard let show else { return }
        do {
            try ListeningRepository(modelContext: context).setWantsLive(showID: show.id, songID: songID, isWanted: !wantedSongIDs.contains(songID))
            try context.save(); try refreshEvidence()
        } catch { context.rollback(); errorText = BSLocalization.text("保存失败，请重试") }
    }
    func filterArtist(_ artistID: String?) {
        selectScope(artistID.map(ListeningBrowseState.Scope.artist) ?? .all)
    }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        try await artistSearchService.searchArtists(query: query)
    }

    func selectScope(_ scope: ListeningBrowseState.Scope) {
        let validArtistIDs = Set(browseArtists.map(\.id))
        browser.select(scope, validArtistIDs: validArtistIDs)
        if case let .artist(artistID) = browser.scope {
            scheduleSelectedArtistCatalogLoadIfNeeded(for: artistID)
        }
    }

    private func scheduleSelectedArtistCatalogLoadIfNeeded(for artistID: String) {
        guard active, access.authorizationStatus == .authorized else { return }

        let needsFullCatalog: Bool
        if let snapshot = catalogSnapshots.first(where: { $0.artistID == artistID }) {
            needsFullCatalog = ListeningCatalogRefreshPolicy.shouldRefresh(
                fetchedAt: snapshot.fetchedAt,
                now: Date()
            )
        } else {
            needsFullCatalog = true
        }

        guard needsFullCatalog else {
            loadFeaturedPlaylistsIfNeeded(for: artistID)
            return
        }

        guard !isLoadingShow, !isCatalogEnriching else { return }

        Task { @MainActor [weak self] in
            guard let self,
                  case let .artist(currentArtistID) = self.browser.scope,
                  currentArtistID == artistID else { return }
            await self.reloadCatalog()
        }
    }
    private func loadFeaturedPlaylistsIfNeeded(for artistID: String) {
        guard active,
              access.authorizationStatus == .authorized,
              loadedFeaturedPlaylistArtistIDs.contains(artistID) == false,
              featuredPlaylistTasks[artistID] == nil,
              catalogSnapshots.contains(where: { $0.artistID == artistID }) else { return }

        let generation = catalogGeneration
        let showID = show?.id
        let service = catalogService
        let store = catalogStore
        featuredPlaylistTasks[artistID] = Task { @MainActor [weak self] in
            defer { self?.featuredPlaylistTasks[artistID] = nil }
            do {
                let payload = try await service.fetchFeaturedPlaylists(
                    artistID: artistID,
                    fetchedAt: Date()
                )
                guard let self,
                      !Task.isCancelled,
                      generation == self.catalogGeneration,
                      showID == self.show?.id else { return }

                let persisted = try await store.persistFeaturedPlaylists(payload)
                guard !Task.isCancelled,
                      generation == self.catalogGeneration,
                      showID == self.show?.id else { return }
                guard persisted else { return }

                self.loadedFeaturedPlaylistArtistIDs.insert(artistID)
                try self.rebuildDiscs()
            } catch is CancellationError {
                return
            } catch {
                // Browse-only failures never downgrade the complete core catalog.
                return
            }
        }
    }
    private func cancelFeaturedPlaylistTasks(clearLoaded: Bool = false) {
        for task in featuredPlaylistTasks.values { task.cancel() }
        featuredPlaylistTasks.removeAll()
        if clearLoaded { loadedFeaturedPlaylistArtistIDs.removeAll() }
    }
    var browsingArtist: ListeningBrowseArtist? {
        guard case let .artist(id) = browser.scope else { return nil }
        return browseArtists.first { $0.id == id }
    }
    var libraryDiscs: [ListeningDisc] {
        switch browser.scope {
        case .all: compilationDiscs
        case .artist: browsingArtist?.albums ?? []
        }
    }
    var shelfDiscs: [ListeningDisc] { display.shelfDiscs }
    func isPlayingDisc(_ disc: ListeningDisc) -> Bool {
        guard display.player.isPlaybackActive,
              mechanism.hasDisc,
              mechanism.disc?.id == disc.id else {
            return false
        }
        return libraryDiscs.contains { $0.id == disc.id }
    }
    func excludeArtist(_ artistID: String, excluded: Bool) {
        guard let show else { return }
        do {
            try ListeningRepository(modelContext: context).setArtistExcluded(showID: show.id, artistID: artistID, isExcluded: excluded)
            try context.save(); if onlyArtistID == artistID && excluded { selectScope(.all) }; try rebuildDiscs()
        } catch { context.rollback(); errorText = BSLocalization.text("保存失败，请重试") }
    }
    func rematch(slotIndex: Int, artist: RecognizedArtist) async {
        guard let show, slotIndex >= 0, slotIndex <= show.artists.count else { return }
        do {
            var artists = show.artists
            if slotIndex == artists.count { artists.append(ArtistSlot(name: artist.canonicalName, avatarURL: nil)) }
            artists[slotIndex].name = artist.canonicalName
            artists[slotIndex].appleMusicArtistID = artist.id
            artists[slotIndex].appleMusicURL = artist.appleMusicURL?.absoluteString
            artists[slotIndex].avatarURL = artist.avatarURL?.absoluteString
            show.artists = artists
            show.updatedAt = Date()
            _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context)
            try context.save()
        } catch {
            context.rollback()
            errorText = BSLocalization.text("保存失败，请重试")
            return
        }

        // Artist confirmation is a local identity mutation. Publish it immediately
        // without rebuilding the room or touching the playback transport; catalog
        // enrichment happens independently after the confirmation can dismiss.
        showCatalogKey = catalogKey(for: show)
        completedCatalogKey = nil
        do {
            try rebuildDiscs()
            selectScope(.artist(artist.id))
        } catch {
            catalogState = .cacheFailed
        }

        // Selecting the confirmed artist owns any detailed-catalog load. If an
        // initial show load is still active, the pending browse request is started
        // when that load releases its identity/catalog generation.
    }
    /// Seats a record silently, as a relaunch does, without playing it.
    func restoreDisc(_ disc: ListeningDisc, songID: String? = nil) {
        guard mechanism.position == .stored, !busy else { return }
        mechanism.restoreSeated(disc)
        deck.load(queueDiscs(for: disc), cursor: songID)
        persistLoadedDisc(force: true)
        prewarmLoadedDisc()
    }
    func loadDisc(_ disc: ListeningDisc, songID: String? = nil, autoplay: Bool = true) {
        if mechanism.disc == disc, mechanism.position == .seated {
            guard let songID else { return }
            selectTrack(songID, autoplay: autoplay)
            return
        }
        runMachine { [self] in
            deck.endSession()
            try await mechanism.load(disc)
            deck.load(queueDiscs(for: disc), cursor: songID)
            persistLoadedDisc(force: true)
            if autoplay {
                startPlaybackIfPossible()
            } else {
                prewarmLoadedDisc()
            }
        }
    }
    func playFromSleeve(_ disc: ListeningDisc, songID: String) {
        guard !busy, !mechanism.isAutomatic else { return }
        guard discs.contains(where: { $0.id == disc.id }),
              let selectedTrack = disc.tracks.first(where: { $0.id == songID }),
              playbackSource(for: selectedTrack) != nil else {
            playbackError = BSLocalization.text("暂不可播放")
            return
        }
        playbackError = nil
        if mechanism.disc == disc, track?.id == songID, wantsPlayback {
            return
        }
        guard mechanism.disc == disc, mechanism.position == .seated else {
            loadDisc(disc, songID: songID)
            return
        }
        guard mechanism.isClosed else {
            runMachine { [self] in
                try await mechanism.closeForPlayback()
                selectTrack(songID, autoplay: true)
            }
            return
        }
        selectTrack(songID, autoplay: true)
    }
    private func selectTrack(_ songID: String, autoplay: Bool) {
        guard mechanism.position == .seated, !mechanism.isAutomatic,
              let target = deck.tracks.first(where: { $0.id == songID }) else { return }
        playbackError = nil
        deck.select(songID, autoplay: autoplay, source: playbackSource(for: target))
    }
    func playPause() {
        guard mechanism.position == .seated, !mechanism.isAutomatic else { return }
        switch playPauseAction {
        case .pause:
            deck.pause()
        case .play:
            startPlayback()
        case .disabled:
            return
        }
    }
    func retryCurrentPlayback() {
        guard mechanism.position == .seated, !mechanism.isAutomatic,
              display.player.recoveryAction == .retryPlayback else { return }
        startPlayback()
    }

    private func startPlayback() {
        playbackError = nil
        guard mechanism.isClosed else {
            runMachine { [self] in
                try await mechanism.closeForPlayback()
                startPlaybackIfPossible()
            }
            return
        }
        startPlaybackIfPossible()
    }

    private func startPlaybackIfPossible() {
        if let disc = mechanism.disc {
            deck.replaceIdleDiscs(queueDiscs(for: disc))
        }
        guard let track = deck.currentTrack, let source = playbackSource(for: track) else { return }
        deck.play(source: source)
    }

    /// Resolves the seated record's songs ahead of the first Play, so a
    /// restored disc starts as fast as one that was just playing.
    private func prewarmLoadedDisc() {
        guard mechanism.position == .seated, let track,
              playbackSource(for: track) == .fullCatalog else { return }
        if let disc = mechanism.disc {
            deck.replaceIdleDiscs(queueDiscs(for: disc))
        }
        deck.prefetch(source: .fullCatalog)
    }

    /// Real records own only their physical disc. BeforeShow compilations are
    /// visible virtual volumes that play as one continuous queue.
    private func queueDiscs(for disc: ListeningDisc) -> [ListeningDisc] {
        guard case let .compilation(showID, _) = disc.origin,
              showID == show?.id,
              compilationDiscs.contains(disc) else { return [disc] }
        return compilationDiscs
    }

    func skip(_ delta: Int) {
        guard delta != 0,
              mechanism.position == .seated,
              mechanism.isClosed,
              !mechanism.isAutomatic,
              let targetID = deck.adjacentSongID(delta),
              let target = deck.tracks.first(where: { $0.id == targetID }) else { return }
        deck.skip(by: delta, source: playbackSource(for: target))
    }
    func stop() {
        operation?.cancel()
        deck.stop()
        persistLoadedDisc(force: true)
    }

    private func hasConfirmedFullPlaybackCapabilityLoss(_ access: ListeningMusicAccess) -> Bool {
        switch access.authorizationStatus {
        case .denied, .restricted:
            true
        case .authorized:
            access.catalogPlaybackAccess == .accountLimited
        case .notDetermined:
            false
        }
    }

    private func endFullPlaybackSessionForCapabilityLossIfNeeded(_ access: ListeningMusicAccess) {
        guard hasConfirmedFullPlaybackCapabilityLoss(access),
              deck.source == .fullCatalog else { return }
        deck.endSession()
        persistLoadedDisc(force: true)
    }

    func tickMechanism() {
        mechanism.refresh()
    }

    private func refreshPlaybackEvidenceProjection() {
        do {
            try refreshEvidence()
            if let show {
                openingTiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>())
                    .filter { $0.showID == show.id }
            }
        } catch {
            errorText = BSLocalization.text("保存失败，请重试")
        }
    }

    private func playbackEvidenceCoordinatorForUse() throws -> ListeningPlaybackEvidenceCoordinator {
        if let playbackEvidenceCoordinator {
            return playbackEvidenceCoordinator
        }
        let created = try evidenceCoordinatorFactory(context)
        playbackEvidenceCoordinator = created
        return created
    }

    private func applyDeckEvidence(
        _ result: ListeningPlaybackEvidenceDrainResult,
        representDismissedAlert: Bool
    ) {
        if result.committedAny {
            refreshPlaybackEvidenceProjection()
        }
        if result.hasFailure {
            handlePlaybackEvidenceFailure(representDismissedAlert: representDismissedAlert)
        }
    }

    private func applyPlaybackEvidenceDrainResult(
        _ result: ListeningPlaybackEvidenceDrainResult
    ) {
        if result.committedAny {
            refreshPlaybackEvidenceProjection()
        }
        if result.hasFailure {
            handlePlaybackEvidenceFailure()
        } else {
            handlePlaybackEvidenceRecovery()
        }
    }

    private var playbackEvidenceFailureMessage: String {
        BSLocalization.text("保存失败，请重试")
    }

    private func handlePlaybackEvidenceFailure(
        representDismissedAlert: Bool = true
    ) {
        evidenceRetryPending = true
        if errorText == nil,
           representDismissedAlert || !evidenceFailureAlertShown {
            evidenceFailureAlertShown = true
            errorText = playbackEvidenceFailureMessage
            evidenceFailureOwnsErrorText = true
        }
        schedulePlaybackEvidenceRetry()
    }

    private func handlePlaybackEvidenceRecovery() {
        guard evidenceRetryPending
                || evidenceFailureAlertShown
                || evidenceFailureOwnsErrorText else {
            return
        }
        evidenceRetryPending = false
        evidenceFailureAlertShown = false
        if evidenceFailureOwnsErrorText,
           errorText == playbackEvidenceFailureMessage {
            errorText = nil
        }
        evidenceFailureOwnsErrorText = false
    }

    func retryPendingPlaybackEvidence() {
        guard let playbackEvidenceCoordinator else { return }
        do {
            applyPlaybackEvidenceDrainResult(
                try playbackEvidenceCoordinator.flushPending()
            )
        } catch {
            handlePlaybackEvidenceFailure()
        }
    }

    private func schedulePlaybackEvidenceRetry() {
        guard evidenceRetryTask == nil else { return }
        evidenceRetryTask = Task { @MainActor [weak self] in
            defer { self?.evidenceRetryTask = nil }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, let evidence = self.playbackEvidenceCoordinator else { return }
                do {
                    let result = try evidence.flushPending()
                    if result.committedAny {
                        self.refreshPlaybackEvidenceProjection()
                    }
                    if result.hasFailure {
                        continue
                    }
                    self.handlePlaybackEvidenceRecovery()
                    return
                } catch {
                    continue
                }
            }
        }
    }

    func setForeground(_ value: Bool) {
        let wasForeground = foreground
        foreground = value
        // Observation catches up on its own; returning from suspension is
        // also an explicit boundary to re-read the player.
        if value, !wasForeground {
            deck.resynchronize()
        }
        updateMotion()
    }
    func setActive(_ value: Bool) {
        active = value
        if value {
            if case let .artist(artistID) = browser.scope {
                scheduleSelectedArtistCatalogLoadIfNeeded(for: artistID)
            }
        } else {
            cancelFeaturedPlaylistTasks()
        }
        updateMotion()
    }
    /// Listening is a secondary task: tab changes and backgrounding never
    /// touch the transport, only the mechanism's display link.
    private func updateMotion() {
        if active && foreground {
            mechanism.motion.wake()
        } else {
            mechanism.motion.pause()
        }
    }
    func returnToWholeShow() { selectScope(.all) }
    /// 等待排队中的装碟操作和播放命令完成，供小组件乐观状态之后按真实结果回写。
    func settlePendingOperation() async {
        await operation?.value
        await deck.settle()
    }

    /// Serializes mechanical sequences: a disc swap, or closing the lid before Play.
    private func runMachine(_ action: @escaping @MainActor () async throws -> Void) {
        let previous = operation
        previous?.cancel()
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            self.busy = true
            defer { self.busy = false }
            do {
                try await action()
            } catch is CancellationError {
            } catch {
                self.playbackError = BSLocalization.text("暂时无法播放")
            }
        }
    }
}
