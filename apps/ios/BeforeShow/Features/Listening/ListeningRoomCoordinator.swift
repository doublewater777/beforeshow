import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct ListeningRuntimeCatalogFetch: Sendable {
    let artistID: String
    let songs: [ListeningCatalogSongPayload]
    let failed: Bool
}

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
        trackIndex = 0
        preparedSongID = nil
        playbackState = .idle
        trackBelongsToShow = true
    }
    #endif
    private(set) var catalogState: CatalogState = .loading
    private(set) var access = ListeningMusicAccess(authorizationStatus: .notDetermined, canPlayCatalogContent: false)
    private(set) var isAuthorizing = false
    private(set) var isCatalogEnriching = false
    private(set) var playbackState: ListeningPlaybackState = .idle {
        didSet {
            let nowPlaying: Bool
            if case .playing = playbackState { nowPlaying = true } else { nowPlaying = false }
            if isPlaying != nowPlaying {
                isPlaying = nowPlaying
                mechanism.motion.spinning = nowPlaying
            }
            updateTimeText()
        }
    }
    private(set) var isPlaying: Bool = false
    private(set) var timeText: String = "00:00"
    private(set) var trackIndex = 0
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
    private(set) var busy = false
    private(set) var sleevePlaybackSongID: String?
    @ObservationIgnored private var pendingSleeveSongID: String?
    var errorText: String?
    var playbackError: String?
    @ObservationIgnored private var visibility = ListeningVisibilityPolicy()
    @ObservationIgnored private var foreground = true
    private(set) var accessResolved = false
    @ObservationIgnored private var preparedSource: ListeningPlaybackSource?
    @ObservationIgnored private var runtimeSongs: [String: [CatalogSong]] = [:]
    @ObservationIgnored private var trackBelongsToShow = false
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
    @ObservationIgnored private let playbackFactory: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing
    @ObservationIgnored private var controller: ListeningPlaybackController?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var catalogGeneration = UUID()
    @ObservationIgnored private var showCatalogKey: String?
    @ObservationIgnored private var completedCatalogKey: String?
    @ObservationIgnored private var preparedSongID: String?
    @ObservationIgnored private var preparedDiscID: String?
    @ObservationIgnored private var finishedSongID: String?
    private(set) var initialLoaded = false
    @ObservationIgnored private var isLoadingShow = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var playbackGeneration = UUID()

    init(context: ModelContext, catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
         artistSearchService: any ArtistSearchServicing = AppleMusicArtistSearchService(),
         playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
             $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
         }) {
        self.context = context; self.catalogService = catalogService; self.playbackFactory = playbackFactory
        self.artistSearchService = artistSearchService
        catalogStore = ListeningCatalogStore(modelContext: context, service: catalogService)
        mechanism.onOpen = { [weak self] in
            #if DEBUG
            if self?.opensWithoutStopping == true { return }
            #endif
            self?.stop()
        }
        mechanism.onTransition = { [weak self] transition in
            if transition == "remove" || transition == "store" {
                self?.preparedDiscID = nil
            }
            CDSoundPlayer.shared.play(transition)
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
    }
    var track: ListeningDiscTrack? {
        guard trackBelongsToShow, mechanism.position != .stored, let disc = mechanism.disc, disc.tracks.indices.contains(trackIndex) else { return nil }
        return disc.tracks[trackIndex]
    }
    var elapsed: TimeInterval {
        switch playbackState {
        case let .ready(_, _, time, _), let .playing(_, _, time, _), let .paused(_, _, time, _): time
        case let .finished(_, _, duration): duration ?? 0
        default: 0
        }
    }
    private func updateTimeText() {
        let time = elapsed.isFinite ? Int(max(0, min(elapsed, 86400))) : 0
        let formatted = String(format: "%02d:%02d", time / 60, time % 60)
        if timeText != formatted {
            timeText = formatted
        }
    }
    func capability(for track: ListeningDiscTrack?) -> ListeningMusicCapability {
        ListeningMusicCapabilityResolver.resolve(access: access, hasPreviewAsset: track?.previewURL != nil, hasCatalogMetadata: track != nil)
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

    func load(show: Show, force: Bool = false) async {
        let generation = UUID()
        catalogGeneration = generation
        isLoadingShow = true
        defer {
            if generation == catalogGeneration {
                isLoadingShow = false
            }
        }

        let newKey = catalogKey(for: show)
        if self.show?.id != show.id {
            initialLoaded = false
            browser = ListeningBrowseState()
            pendingSleeveSongID = nil
            sleevePlaybackSongID = nil
            recentListening = nil
            preparedDiscID = nil
        }
        if showCatalogKey != newKey {
            completedCatalogKey = nil
            stop(); trackBelongsToShow = false; discs = []; runtimeSongs = [:]
            preparedDiscID = nil
            if mechanism.hasDisc || mechanism.position == .removed { run { [self] in try await mechanism.unload() } }
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

        // Keep a known-authorized room in `.connecting` while identity fallback is
        // still running. Imported shows normally arrive pre-matched, so this path is
        // mostly a legacy/manual fallback; publishing full capability waits until it
        // has finished, preserving the first-load presentation contract.
        let slots = show.artists
        let matches = (try? await ListeningArtistAutoMatcher(search: artistSearchService).matches(for: slots)) ?? [:]
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        applyAutomaticArtistMatches(matches, originalSlots: slots, to: show)
        guard generation == catalogGeneration, !Task.isCancelled else { return }

        let newAccess = await catalogService.currentAccess()
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        access = newAccess
        accessResolved = true

        await loadCatalog(generation: generation, force: force)
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        completedCatalogKey = showCatalogKey
    }

    private func applyAutomaticArtistMatches(
        _ matches: [Int: RecognizedArtist],
        originalSlots slots: [ArtistSlot],
        to show: Show
    ) {
        guard !matches.isEmpty else { return }
        do {
            try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
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
            _ = try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context, saveChanges: false)
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
        let generation = UUID()
        catalogGeneration = generation
        catalogState = .loading
        await loadCatalog(generation: generation, force: force)
        if generation == catalogGeneration, !Task.isCancelled {
            initialLoaded = true
            completedCatalogKey = showCatalogKey
        }
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
        let cachedIDs = Set(catalogSnapshots.map(\.artistID))
        let quickIDs = ids.filter { !cachedIDs.contains($0) && runtimeSongs[$0] == nil }

        // Stage 1: fetch all top-song previews concurrently, then publish one UI
        // update. Festival lineups no longer cause one rebuild per artist.
        if !quickIDs.isEmpty {
            let quickResults = await fetchRuntimeCatalog(for: quickIDs)
            guard generation == catalogGeneration, !Task.isCancelled else { return }
            for result in quickResults {
                if result.failed {
                    failedIDs.insert(result.artistID)
                    continue
                }
                runtimeSongs[result.artistID] = result.songs.map {
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
            do {
                try rebuildDiscs()
                if !discs.isEmpty { catalogState = .ready }
            } catch {
                catalogState = .cacheFailed
            }
        }

        guard generation == catalogGeneration, !Task.isCancelled else { return }

        // Cached complete catalogs are immediately usable. Preserve the store's
        // stale-while-revalidate behavior without waiting on network here.
        if !force {
            for id in ids where cachedIDs.contains(id) {
                do {
                    _ = try await catalogStore.loadArtistCatalog(artistID: id)
                } catch {
                    failedIDs.insert(id)
                }
                guard generation == catalogGeneration, !Task.isCancelled else { return }
            }
        }

        // Stage 2: full catalog network work is concurrent, while persistence remains
        // serialized on MainActor. Publish one final rebuild after every payload has
        // been committed.
        let fullIDs = force ? ids : ids.filter { !cachedIDs.contains($0) }
        if !fullIDs.isEmpty {
            let fullResults = await fetchFullCatalog(for: fullIDs)
            guard generation == catalogGeneration, !Task.isCancelled else { return }
            for result in fullResults {
                guard let payload = result.payload, !result.failed else {
                    failedIDs.insert(result.artistID)
                    continue
                }
                do {
                    _ = try catalogStore.persistArtistCatalog(payload)
                    failedIDs.remove(result.artistID)
                } catch {
                    failedIDs.insert(result.artistID)
                }
                guard generation == catalogGeneration, !Task.isCancelled else { return }
            }
        }

        do {
            try rebuildDiscs()
            catalogState = failedIDs.isEmpty ? (discs.isEmpty ? .unavailable : .ready) : .cacheFailed
        } catch {
            catalogState = .cacheFailed
        }
    }

    private func fetchRuntimeCatalog(for artistIDs: [String]) async -> [ListeningRuntimeCatalogFetch] {
        let service = catalogService
        var results: [ListeningRuntimeCatalogFetch] = []
        var cursor = 0
        while cursor < artistIDs.count, !Task.isCancelled {
            let end = min(cursor + listeningCatalogFetchConcurrency, artistIDs.count)
            let batch = Array(artistIDs[cursor..<end])
            let values = await withTaskGroup(
                of: ListeningRuntimeCatalogFetch.self,
                returning: [ListeningRuntimeCatalogFetch].self
            ) { group in
                for artistID in batch {
                    group.addTask {
                        do {
                            return ListeningRuntimeCatalogFetch(
                                artistID: artistID,
                                songs: try await service.fetchRuntimeSongs(artistID: artistID),
                                failed: false
                            )
                        } catch {
                            return ListeningRuntimeCatalogFetch(artistID: artistID, songs: [], failed: true)
                        }
                    }
                }
                var batchResults: [ListeningRuntimeCatalogFetch] = []
                for await value in group { batchResults.append(value) }
                return batchResults
            }
            results.append(contentsOf: values)
            cursor = end
        }
        return results
    }

    private func fetchFullCatalog(for artistIDs: [String]) async -> [ListeningFullCatalogFetch] {
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
            cursor = end
        }
        return results
    }

    func authorize() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        _ = await catalogService.requestAuthorization()
        let newAccess = await catalogService.currentAccess()
        access = newAccess
        accessResolved = true
        isAuthorizing = false

        guard newAccess.authorizationStatus == .authorized else { return }
        // If initial show preparation is still matching identities, that operation
        // will continue into catalog loading with the newly-authorized access.
        guard !isLoadingShow else { return }
        await reloadCatalog()
    }

    private func rebuildDiscs() throws {
        guard let show else { return }
        excludedArtistIDs = Set(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>())
            .filter { $0.showID == show.id && $0.isExcluded }.map(\.artistID))
        catalogSongs = try context.fetch(FetchDescriptor<CatalogSong>())
        let cachedIDs = Set(catalogSongs.map(\.appleMusicSongID))
        catalogSongs += runtimeSongs.values.flatMap { $0 }.filter { !cachedIDs.contains($0.appleMusicSongID) }
        catalogAlbums = try context.fetch(FetchDescriptor<CatalogAlbum>())
        openingTiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).filter { $0.showID == show.id }
        catalogSnapshots = try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        let songsByID = Dictionary(catalogSongs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { a, _ in a })
        let albumsByID = Dictionary(catalogAlbums.map { ($0.appleMusicAlbumID, $0) }, uniquingKeysWith: { a, _ in a })
        let mappedArtists: [ListeningBrowseArtist] = show.artists.enumerated().map { index, slot in
            if let id = slot.appleMusicArtistID {
                let snapshot = catalogSnapshots.first { $0.artistID == id }
                let albums = (snapshot?.albumIDs ?? []).compactMap { albumsByID[$0] }.filter { $0.isSingle != true }
                return ListeningBrowseArtist(
                    slotIndex: index,
                    id: id,
                    name: slot.name,
                    artworkURL: (slot.avatarURL ?? snapshot?.artworkURL).flatMap(URL.init(string:)),
                    appleMusicArtistID: id,
                    albums: ListeningDiscAssembler.discs(albums: albums, songsByID: songsByID)
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
            if let snapshot = catalogSnapshots.first(where: { $0.artistID == id }) {
                return snapshot.topSongIDs.compactMap { songsByID[$0].map(ListeningDiscTrack.init) }
            }
            return (runtimeSongs[id] ?? []).map(ListeningDiscTrack.init)
        })
        var discIDs = Set<String>()
        discs = (compilationDiscs + browseArtists.flatMap(\.albums)).filter { discIDs.insert($0.id).inserted }
        let connectedIDs = Set(browseArtists.compactMap(\.appleMusicArtistID))
        browser.reconcile(validArtistIDs: connectedIDs)
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
        guard isPlaying, let show, let track, let disc = mechanism.disc,
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
    func selectScope(_ scope: ListeningBrowseState.Scope) {
        let connectedIDs = Set(browseArtists.compactMap(\.appleMusicArtistID))
        browser.select(scope, validArtistIDs: connectedIDs)
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
        guard isPlaying, mechanism.hasDisc, mechanism.disc?.id == disc.id else { return false }
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
            try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
            var artists = show.artists
            if slotIndex == artists.count { artists.append(ArtistSlot(name: artist.canonicalName, avatarURL: nil)) }
            artists[slotIndex].name = artist.canonicalName
            artists[slotIndex].appleMusicArtistID = artist.id
            artists[slotIndex].appleMusicURL = artist.appleMusicURL?.absoluteString
            artists[slotIndex].avatarURL = artist.avatarURL?.absoluteString
            show.artists = artists
            show.updatedAt = Date()
            _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context)
            _ = try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context, saveChanges: false)
            try context.save()
            selectScope(.all)
            await load(show: show)
        } catch { context.rollback(); errorText = BSLocalization.text("保存失败，请重试") }
    }
    func restoreDisc(_ disc: ListeningDisc, songID: String? = nil) {
        guard mechanism.position == .stored, !busy else { return }
        stop()
        mechanism.restoreSeated(disc)
        trackIndex = songID.flatMap { id in disc.tracks.firstIndex { $0.id == id } } ?? 0
        preparedDiscID = nil
        preparedSongID = nil
        playbackState = .idle
        trackBelongsToShow = true
    }
    func loadDisc(_ disc: ListeningDisc, songID: String? = nil, autoplay: Bool = true) {
        if mechanism.disc == disc, mechanism.position == .seated {
            guard songID != nil else { return }
            selectTrack(on: disc, songID: songID, autoplay: autoplay)
            return
        }
        run { [self] in
            stop()
            try await mechanism.load(disc)
            trackIndex = songID.flatMap { id in disc.tracks.firstIndex { $0.id == id } } ?? 0
            preparedSongID = nil; playbackState = .idle; trackBelongsToShow = true
            if autoplay { try await playCurrentTrack() }
        }
    }
    func playFromSleeve(_ disc: ListeningDisc, songID: String) {
        guard !busy, !mechanism.isAutomatic, pendingSleeveSongID == nil else { return }
        sleevePlaybackSongID = nil
        guard discs.contains(where: { $0.id == disc.id }),
              let selectedTrack = disc.tracks.first(where: { $0.id == songID }),
              ListeningPlaybackSourceResolver.resolve(capability: capability(for: selectedTrack)) != nil else {
            playbackError = BSLocalization.text("暂不可播放")
            return
        }
        playbackError = nil
        if mechanism.disc == disc, track?.id == songID, isPlaying {
            sleevePlaybackSongID = songID
            return
        }
        pendingSleeveSongID = songID
        if mechanism.disc == disc, mechanism.position == .seated, !mechanism.isClosed {
            run { [self] in
                try await mechanism.closeForPlayback()
                guard let index = disc.tracks.firstIndex(where: { $0.id == songID }) else { return }
                trackIndex = index; trackBelongsToShow = true
                try await playCurrentTrack()
            }
            return
        }
        loadDisc(disc, songID: songID)
    }
    private func selectTrack(on disc: ListeningDisc, songID: String?, autoplay: Bool) {
        guard mechanism.position == .seated, !mechanism.isAutomatic else { return }
        let nextIndex = songID.flatMap { id in disc.tracks.firstIndex { $0.id == id } } ?? 0
        guard disc.tracks.indices.contains(nextIndex) else { return }
        if disc.id == mechanism.disc?.id, nextIndex == trackIndex {
            if autoplay, !isPlaying { playPause() }
            return
        }
        mechanism.updateContents(disc)
        let resume = autoplay || isPlaying
        run { [self] in
            stop(); trackIndex = nextIndex; trackBelongsToShow = true
            if resume { try await playCurrentTrack() }
        }
    }
    func manualDiscChanged() { guard !mechanism.isAutomatic else { return }; stop(); trackIndex = 0; trackBelongsToShow = true; preparedDiscID = nil }
    func playPause() {
        guard mechanism.position == .seated, !mechanism.isAutomatic else { return }
        if !mechanism.isClosed {
            run { [self] in
                try await mechanism.closeForPlayback()
                try await playCurrentTrack()
            }
            return
        }
        run { [self] in
            if isPlaying { visibility.userPause(); try controller?.pause(); playbackState = controller?.state ?? .idle }
            else { visibility.userPlay(); try await playCurrentTrack() }
        }
    }
    private func playCurrentTrack() async throws {
        guard let track, let disc = mechanism.disc,
              let source = ListeningPlaybackSourceResolver.resolve(capability: capability(for: track)) else {
            pendingSleeveSongID = nil
            return
        }
        playbackError = nil
        let generation = playbackGeneration
        if preparedSongID != track.id || preparedSource != source || controller == nil || playbackState == .failed || playbackState.isFinished {
            try controller?.stop()
            let service = playbackFactory(source)
            let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: context)
            let next = ListeningPlaybackController(service: service, evidenceCoordinator: evidence)
            controller = next
            // Reading the disc: spin-up whir and laser seek only when a new disc
            // is seated. Switching tracks on the same disc or resuming playback stays silent.
            if preparedDiscID != disc.id {
                CDSoundPlayer.shared.play("read")
                preparedDiscID = disc.id
            }
            // A single physical disc owns continuation. The transport receives the
            // whole CD so iOS can advance tracks even while this view is not running.
            try await next.prepare(
                items: disc.tracks.map(\.playbackItem),
                source: source,
                startingAtSongID: track.id
            )
            try Task.checkCancellation()
            guard generation == playbackGeneration, mechanism.isClosed, mechanism.position == .seated else {
                pendingSleeveSongID = nil
                try next.stop()
                return
            }
            preparedSongID = track.id; preparedSource = source
        }
        try await controller?.play()
        try Task.checkCancellation()
        guard generation == playbackGeneration, mechanism.isClosed else {
            pendingSleeveSongID = nil
            try controller?.stop()
            return
        }
        playbackState = controller?.state ?? .idle; finishedSongID = nil
        completeSleevePlaybackIfNeeded()
        recordPlayingIfNeeded()
    }
    private func completeSleevePlaybackIfNeeded() {
        guard isPlaying, let pendingSleeveSongID, track?.id == pendingSleeveSongID else { return }
        sleevePlaybackSongID = pendingSleeveSongID
        self.pendingSleeveSongID = nil
    }
    func skip(_ delta: Int) {
        guard let disc = mechanism.disc, mechanism.position == .seated, mechanism.isClosed else { return }
        let nextIndex = trackIndex + delta
        guard disc.tracks.indices.contains(nextIndex) else { return }
        let resume = isPlaying
        run { [self] in
            stop(); trackIndex = nextIndex
            if resume { try await playCurrentTrack() }
        }
    }
    func stop() {
        recordedPlayingSongID = nil
        playbackGeneration = UUID()
        trackIndex = 0
        do { try controller?.stop() } catch { errorText = BSLocalization.text("熟悉度保存失败，请重试") }
        controller = nil; preparedSongID = nil; preparedSource = nil; playbackState = .idle; finishedSongID = nil; visibility = ListeningVisibilityPolicy(); isPlaying = false; updateTimeText()
    }
    func tick() {
        mechanism.refresh()
        guard !busy, let controller else { return }
        do {
            playbackState = try controller.refresh()
            syncTrackIndexWithPlaybackState()
            if case .failed = playbackState {
                pendingSleeveSongID = nil
                playbackError = BSLocalization.text("暂时无法播放")
                return
            }
            completeSleevePlaybackIfNeeded()
            recordPlayingIfNeeded()
            try refreshEvidence()
            if case let .finished(songID, _, _) = playbackState {
                finishedSongID = songID
            } else {
                finishedSongID = nil
            }
        } catch {
            pendingSleeveSongID = nil
            stop()
            playbackError = BSLocalization.text("暂时无法播放")
        }
    }
    private func syncTrackIndexWithPlaybackState() {
        let songID: String?
        switch playbackState {
        case let .ready(id, _, _, _), let .playing(id, _, _, _), let .paused(id, _, _, _), let .finished(id, _, _):
            songID = id
        case .idle, .preparing, .failed:
            songID = nil
        }
        guard let songID, let disc = mechanism.disc,
              let index = disc.tracks.firstIndex(where: { $0.id == songID }) else { return }
        if trackIndex != index {
            trackIndex = index
            recordedPlayingSongID = nil
        }
        preparedSongID = songID
    }
    func seek(_ time: TimeInterval) {
        guard time.isFinite, time >= 0 else { return }
        do { try controller?.seek(to: time); playbackState = controller?.state ?? .idle }
        catch { playbackError = BSLocalization.text("暂时无法播放") }
    }
    func setForeground(_ value: Bool) { foreground = value; updateVisibility() }
    func setActive(_ value: Bool) { active = value; updateVisibility() }
    private func updateVisibility() {
        let source = preparedSource ?? ListeningPlaybackSourceResolver.resolve(capability: capability(for: track))
        if ListeningVisibilityPolicy.mustPause(tabVisible: active, foreground: foreground, source: source) {
            visibility.interrupt(wasPlaying: isPlaying)
            do { try controller?.pause(); playbackState = controller?.state ?? .idle }
            catch { playbackError = BSLocalization.text("暂时无法播放") }
        } else if visibility.resumeIfAllowed() {
            run { [self] in try await playCurrentTrack() }
        }
        if active && foreground { mechanism.motion.start() }
        // Keep mechanical transactions settling even when their page is hidden.
    }
    func returnToWholeShow() { selectScope(.all) }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        let previous = operation
        previous?.cancel()
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            self.busy = true
            defer { self.busy = false }
            do { try await action() }
            catch is CancellationError { self.pendingSleeveSongID = nil; self.stop() }
            catch { self.pendingSleeveSongID = nil; self.stop(); self.playbackError = BSLocalization.text("暂时无法播放") }
        }
    }
}
