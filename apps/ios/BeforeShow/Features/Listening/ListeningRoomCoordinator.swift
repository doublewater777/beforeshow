import SwiftUI
import SwiftData

@MainActor @Observable final class ListeningRoomCoordinator {
    enum CatalogState { case loading, ready, unmatched, cacheFailed, unavailable }
    let mechanism = CDMechanism()
    private(set) var catalogSongs: [CatalogSong] = []
    private(set) var catalogAlbums: [CatalogAlbum] = []
    private(set) var openingTiers: [ShowOpeningArtistTier] = []
    private(set) var catalogSnapshots: [ArtistCatalogSnapshot] = []
    private(set) var show: Show?
    private(set) var discs: [ListeningDisc] = []
    private(set) var catalogState: CatalogState = .loading
    private(set) var access = ListeningMusicAccess(authorizationStatus: .notDetermined, canPlayCatalogContent: false)
    private(set) var playbackState: ListeningPlaybackState = .idle
    private(set) var trackIndex = 0
    private(set) var wantedSongIDs: Set<String> = []
    private(set) var familiarSongIDs: Set<String> = []
    private(set) var excludedArtistIDs: Set<String> = []
    private(set) var onlyArtistID: String?
    private(set) var busy = false
    var errorText: String?
    var playbackError: String?
    private var visibility = ListeningVisibilityPolicy()
    private var foreground = true
    private var accessResolved = false
    private var preparedSource: ListeningPlaybackSource?
    private var runtimeSongs: [String: [CatalogSong]] = [:]
    private var trackBelongsToShow = false
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
    @ObservationIgnored private let catalogStore: ListeningCatalogStore
    @ObservationIgnored private let playbackFactory: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing
    @ObservationIgnored private var controller: ListeningPlaybackController?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var catalogGeneration = UUID()
    @ObservationIgnored private var showCatalogKey: String?
    @ObservationIgnored private var preparedSongID: String?
    @ObservationIgnored private var finishedSongID: String?
    @ObservationIgnored private var active = true
    @ObservationIgnored private var playbackGeneration = UUID()

    init(context: ModelContext, catalogService: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService(),
         playbackFactory: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing = {
             $0 == .fullCatalog ? MusicKitListeningPlaybackService() : PreviewListeningPlaybackService()
         }) {
        self.context = context; self.catalogService = catalogService; self.playbackFactory = playbackFactory
        catalogStore = ListeningCatalogStore(modelContext: context, service: catalogService)
        mechanism.onOpen = { [weak self] in self?.stop() }
    }
    var track: ListeningDiscTrack? {
        guard trackBelongsToShow, mechanism.position != .stored, let disc = mechanism.disc, disc.tracks.indices.contains(trackIndex) else { return nil }
        return disc.tracks[trackIndex]
    }
    var isPlaying: Bool { if case .playing = playbackState { true } else { false } }
    var elapsed: TimeInterval {
        switch playbackState {
        case let .ready(_, _, time, _), let .playing(_, _, time, _), let .paused(_, _, time, _): time
        case let .finished(_, _, duration): duration ?? 0
        default: 0
        }
    }
    var timeText: String { let time = elapsed.isFinite ? Int(max(0, min(elapsed, 86400))) : 0; return String(format: "%02d:%02d", time / 60, time % 60) }
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
    func load(show: Show, force: Bool = false) async {
        let generation = UUID(); catalogGeneration = generation
        let newKey = show.id.uuidString + show.artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
        if showCatalogKey != newKey {
            stop(); onlyArtistID = nil; trackBelongsToShow = false; discs = []; runtimeSongs = [:]
            if mechanism.hasDisc || mechanism.position == .removed { run { [self] in try await mechanism.unload() } }
        }
        showCatalogKey = newKey
        self.show = show; catalogState = .loading; accessResolved = false
        do {
            try rebuildDiscs()
            if mechanism.position == .stored && !busy, let first = discs.first { loadDisc(first) }
        } catch { catalogState = .cacheFailed }
        let newAccess = await catalogService.currentAccess()
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        access = newAccess; accessResolved = true
        let ids = show.artists.compactMap(\.appleMusicArtistID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !ids.isEmpty else { discs = []; catalogState = .unmatched; return }
        var failed = false
        for id in ids {
            do {
                if access.authorizationStatus == .authorized {
                    if !catalogSnapshots.contains(where: { $0.artistID == id }) {
                        let first = try await catalogService.fetchRuntimeSongs(artistID: id)
                        guard generation == catalogGeneration, !Task.isCancelled else { return }
                        runtimeSongs[id] = first.map {
                            CatalogSong(appleMusicSongID: $0.songID, title: $0.title, artistName: $0.artistName,
                                artworkURL: $0.artworkURL, duration: $0.duration, performerArtistIDs: $0.performerArtistIDs, previewURL: $0.previewURL)
                        }
                        try rebuildDiscs()
                        if !discs.isEmpty { catalogState = .ready }
                        if mechanism.position == .stored && !busy, let first = discs.first { loadDisc(first) }
                    }
                    _ = try await catalogStore.refreshArtistCatalog(artistID: id)
                }
                guard generation == catalogGeneration, !Task.isCancelled else { return }
                try rebuildDiscs()
                if !discs.isEmpty { catalogState = .ready }
                if mechanism.position == .stored && !busy, let first = discs.first { loadDisc(first) }
            } catch { failed = true }
            guard generation == catalogGeneration, !Task.isCancelled else { return }
        }
        do {
            try rebuildDiscs()
            catalogState = failed ? .cacheFailed : (discs.isEmpty ? .unavailable : .ready)
        } catch { catalogState = .cacheFailed }
    }
    func authorize() async {
        _ = await catalogService.requestAuthorization()
        if let show { await load(show: show) }
    }
    private func rebuildDiscs() throws {
        guard let show else { return }
        excludedArtistIDs = Set(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>())
            .filter { $0.showID == show.id && $0.isExcluded }.map(\.artistID))
        let queue = try ListeningQueueProvider(modelContext: context).queue(showID: show.id, onlyArtistID: onlyArtistID, runtimeSongIDs: runtimeSongs.mapValues { $0.map(\.appleMusicSongID) })
        catalogSongs = try context.fetch(FetchDescriptor<CatalogSong>())
        let cachedIDs = Set(catalogSongs.map(\.appleMusicSongID))
        catalogSongs += runtimeSongs.values.flatMap { $0 }.filter { !cachedIDs.contains($0.appleMusicSongID) }
        catalogAlbums = try context.fetch(FetchDescriptor<CatalogAlbum>())
        openingTiers = try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).filter { $0.showID == show.id }
        catalogSnapshots = try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        discs = ListeningDiscAssembler.discs(albums: catalogAlbums, songs: catalogSongs, queue: queue)
        try refreshEvidence()
        refreshCompilation()
    }
    private func refreshEvidence() throws {
        guard let show else { return }
        wantedSongIDs = Set(try context.fetch(FetchDescriptor<ShowWantsLiveSong>()).filter { $0.showID == show.id }.map(\.songID))
        familiarSongIDs = FamiliarityEvidenceResolver.familiarSongIDs(
            records: try context.fetch(FetchDescriptor<SongFamiliarityRecord>()),
            setlistMemories: try context.fetch(FetchDescriptor<ShowSetlistMemory>()))
    }
    func toggleWanted(_ songID: String) {
        guard let show else { return }
        do {
            try ListeningRepository(modelContext: context).setWantsLive(showID: show.id, songID: songID, isWanted: !wantedSongIDs.contains(songID))
            try context.save(); try refreshEvidence()
        } catch { context.rollback(); errorText = BSLocalization.text("保存失败，请重试") }
    }
    func filterArtist(_ artistID: String?) {
        onlyArtistID = artistID; stop()
        do {
            try rebuildDiscs()
            if let first = discs.first { loadDisc(first) }
            else { run { [self] in try await mechanism.unload() } }
        } catch { errorText = BSLocalization.text("缓存读取失败") }
    }
    func excludeArtist(_ artistID: String, excluded: Bool) {
        guard let show else { return }
        do {
            try ListeningRepository(modelContext: context).setArtistExcluded(showID: show.id, artistID: artistID, isExcluded: excluded)
            try context.save(); if onlyArtistID == artistID && excluded { onlyArtistID = nil }; stop(); try rebuildDiscs()
            if let first = discs.first { loadDisc(first) }
            else { run { [self] in try await mechanism.unload() } }
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
            onlyArtistID = nil
            await load(show: show)
        } catch { context.rollback(); errorText = BSLocalization.text("保存失败，请重试") }
    }
    func loadDisc(_ disc: ListeningDisc, songID: String? = nil, autoplay: Bool = false) {
        run { [self] in
            stop()
            try await mechanism.load(disc)
            trackIndex = songID.flatMap { id in disc.tracks.firstIndex { $0.id == id } } ?? 0
            preparedSongID = nil; playbackState = .idle; trackBelongsToShow = true
            if autoplay { try await playCurrentTrack() }
        }
    }
    func manualDiscChanged() { guard !mechanism.isAutomatic else { return }; stop(); trackIndex = 0; trackBelongsToShow = true }
    func playPause() {
        guard mechanism.isClosed, mechanism.position == .seated, !mechanism.isAutomatic else { return }
        run { [self] in
            if isPlaying { visibility.userPause(); try controller?.pause(); playbackState = controller?.state ?? .idle }
            else { visibility.userPlay(); try await playCurrentTrack() }
        }
    }
    private func playCurrentTrack() async throws {
        guard let track, let source = ListeningPlaybackSourceResolver.resolve(capability: capability(for: track)) else { return }
        playbackError = nil
        let generation = playbackGeneration
        if preparedSongID != track.id || preparedSource != source || controller == nil {
            try controller?.stop()
            let service = playbackFactory(source)
            let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: context)
            let next = ListeningPlaybackController(service: service, evidenceCoordinator: evidence)
            controller = next
            // A single physical disc owns continuation. Preparing one track also
            // prevents MusicKit recommendations, shuffle or another disc taking over.
            try await next.prepare(items: [track.playbackItem], source: source)
            try Task.checkCancellation()
            guard generation == playbackGeneration, active, (foreground || source == .fullCatalog), mechanism.isClosed, mechanism.position == .seated else { try next.stop(); return }
            preparedSongID = track.id; preparedSource = source
        }
        try await controller?.play()
        try Task.checkCancellation()
        guard generation == playbackGeneration, active, (foreground || source == .fullCatalog), mechanism.isClosed else { try controller?.stop(); return }
        playbackState = controller?.state ?? .idle; finishedSongID = nil
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
        playbackGeneration = UUID()
        do { try controller?.stop() } catch { errorText = BSLocalization.text("熟悉度保存失败，请重试") }
        controller = nil; preparedSongID = nil; preparedSource = nil; playbackState = .idle; finishedSongID = nil; visibility = ListeningVisibilityPolicy()
    }
    private func refreshCompilation() {
        guard trackBelongsToShow, !mechanism.isAutomatic, mechanism.disc?.id == "preparation",
              let updated = discs.first, updated.id == "preparation", updated != mechanism.disc,
              let currentID = track?.id, let index = updated.tracks.firstIndex(where: { $0.id == currentID }) else { return }
        mechanism.updateContents(updated); trackIndex = index
    }
    func tick() {
        mechanism.refresh()
        refreshCompilation()
        guard !busy, let controller else { return }
        do {
            playbackState = try controller.refresh()
            try refreshEvidence()
            if case let .finished(songID, _, _) = playbackState, finishedSongID != songID {
                finishedSongID = songID
                if let disc = mechanism.disc, trackIndex + 1 < disc.tracks.count {
                    run { [self] in
                        try self.controller?.stop(); preparedSongID = nil
                        trackIndex += 1; try await playCurrentTrack()
                    }
                }
                else { try controller.stop(); self.controller = nil; preparedSongID = nil }
                // Last track stays finished. No disc swap or wraparound.
            }
        } catch { stop(); playbackError = BSLocalization.text("暂时无法播放") }
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
    func returnToWholeShow() {
        onlyArtistID = nil
        do { try rebuildDiscs(); if let disc = discs.first { loadDisc(disc) } }
        catch { errorText = BSLocalization.text("缓存读取失败") }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        let previous = operation
        previous?.cancel()
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            self.busy = true
            defer { self.busy = false }
            do { try await action() }
            catch is CancellationError { self.stop() }
            catch { self.stop(); self.playbackError = BSLocalization.text("暂时无法播放") }
        }
    }
}
