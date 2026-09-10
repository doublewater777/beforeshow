import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
    private(set) var isAuthorizing = false
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
    @ObservationIgnored private var accessResolved = false
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
    @ObservationIgnored private var preparedSongID: String?
    @ObservationIgnored private var finishedSongID: String?
    private(set) var initialLoaded = false
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
        mechanism.onOpen = { [weak self] in self?.stop() }
        mechanism.onTransition = { transition in
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
        CDSoundPlayer.shared.warmup()
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
    func load(show: Show, force: Bool = false) async {
        let generation = UUID(); catalogGeneration = generation
        let newKey = show.id.uuidString + show.artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
        if self.show?.id != show.id {
            browser = ListeningBrowseState()
            pendingSleeveSongID = nil
            sleevePlaybackSongID = nil
            recentListening = nil
        }
        if showCatalogKey != newKey {
            stop(); trackBelongsToShow = false; discs = []; runtimeSongs = [:]
            if mechanism.hasDisc || mechanism.position == .removed { run { [self] in try await mechanism.unload() } }
        }
        showCatalogKey = newKey
        self.show = show; catalogState = .loading; accessResolved = false
        do {
            try rebuildDiscs()
        } catch { catalogState = .cacheFailed }
        let slots = show.artists
        let matches = (try? await ListeningArtistAutoMatcher(search: artistSearchService).matches(for: slots)) ?? [:]
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        do {
            if !matches.isEmpty {
                try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
                var artists = show.artists
                for (index, candidate) in matches {
                    guard artists.indices.contains(index), artists[index].name == slots[index].name,
                          artists[index].appleMusicArtistID == nil else { continue }
                    artists[index].appleMusicArtistID = candidate.id
                    artists[index].appleMusicURL = candidate.appleMusicURL?.absoluteString
                    if artists[index].avatarURL == nil { artists[index].avatarURL = candidate.avatarURL?.absoluteString }
                }
                show.artists = artists
                show.updatedAt = Date()
                _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(in: context)
                _ = try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context, saveChanges: false)
                try context.save()
                showCatalogKey = show.id.uuidString + artists.map { $0.name + ($0.appleMusicArtistID ?? "") }.joined(separator: "|")
                try rebuildDiscs()
            }
        } catch { context.rollback() }
        let newAccess = await catalogService.currentAccess()
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        access = newAccess; accessResolved = true; initialLoaded = true
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
                    }
                    if force {
                        _ = try await catalogStore.refreshArtistCatalog(artistID: id)
                    } else {
                        _ = try await catalogStore.loadArtistCatalog(artistID: id)
                    }
                }
                guard generation == catalogGeneration, !Task.isCancelled else { return }
               try rebuildDiscs()
               if !discs.isEmpty { catalogState = .ready }
            } catch { failed = true }
            guard generation == catalogGeneration, !Task.isCancelled else { return }
        }
        do {
            try rebuildDiscs()
            catalogState = failed ? .cacheFailed : (discs.isEmpty ? .unavailable : .ready)
        } catch { catalogState = .cacheFailed }
    }
    func authorize() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        _ = await catalogService.requestAuthorization()
        let newAccess = await catalogService.currentAccess()
        access = newAccess; accessResolved = true
        if let show { await load(show: show) }
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
    var shelfDiscs: [ListeningDisc] { libraryDiscs }
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
    func manualDiscChanged() { guard !mechanism.isAutomatic else { return }; stop(); trackIndex = 0; trackBelongsToShow = true }
    func playPause() {
        guard mechanism.isClosed, mechanism.position == .seated, !mechanism.isAutomatic else { return }
        run { [self] in
            if isPlaying { visibility.userPause(); try controller?.pause(); playbackState = controller?.state ?? .idle }
            else { visibility.userPlay(); try await playCurrentTrack() }
        }
    }
    private func playCurrentTrack() async throws {
        guard let track, let source = ListeningPlaybackSourceResolver.resolve(capability: capability(for: track)) else {
            pendingSleeveSongID = nil
            return
        }
        playbackError = nil
        let generation = playbackGeneration
        if preparedSongID != track.id || preparedSource != source || controller == nil {
            try controller?.stop()
            let service = playbackFactory(source)
            let evidence = try ListeningPlaybackEvidenceCoordinator(modelContext: context)
            let next = ListeningPlaybackController(service: service, evidenceCoordinator: evidence)
            controller = next
            // Reading the disc: spin-up whir and laser seek while a new track
            // prepares. Pause/resume reuses the prepared track and stays silent.
            CDSoundPlayer.shared.play("read")
            // A single physical disc owns continuation. Preparing one track also
            // prevents MusicKit recommendations, shuffle or another disc taking over.
            try await next.prepare(items: [track.playbackItem], source: source)
            try Task.checkCancellation()
            guard generation == playbackGeneration, active, (foreground || source == .fullCatalog), mechanism.isClosed, mechanism.position == .seated else {
                pendingSleeveSongID = nil
                try next.stop()
                return
            }
            preparedSongID = track.id; preparedSource = source
        }
        try await controller?.play()
        try Task.checkCancellation()
        guard generation == playbackGeneration, active, (foreground || source == .fullCatalog), mechanism.isClosed else {
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
            if case .failed = playbackState {
                pendingSleeveSongID = nil
                playbackError = BSLocalization.text("暂时无法播放")
                return
            }
            completeSleevePlaybackIfNeeded()
            recordPlayingIfNeeded()
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
        } catch {
            pendingSleeveSongID = nil
            stop()
            playbackError = BSLocalization.text("暂时无法播放")
        }
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
