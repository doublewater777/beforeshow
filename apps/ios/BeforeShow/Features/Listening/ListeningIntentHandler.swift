import Foundation
import SwiftData

// MARK: - Listening Intent Handler
// 在主 App 进程中执行小组件的播放或暂停。命令串行进入「听」模块，不改写快照来假装已经生效。

@MainActor
final class ListeningIntentHandler: ListeningIntentHandling {
    static let shared = ListeningIntentHandler()

    private var modelContainer: ModelContainer?
    private var commandChain: Task<Void, Never> = Task {}
    var playbackDependencies: ListeningWidgetPlaybackDependencies?

    private init() {}

    func configure(with container: ModelContainer) {
        modelContainer = container
    }

    func perform(_ command: ListeningWidgetCommand) async {
        let previous = commandChain
        let next = Task { @MainActor in
            await previous.value
            await self.apply(command)
        }
        commandChain = next
        await next.value
    }

    private func apply(_ command: ListeningWidgetCommand) async {
        guard let room = await resolveRoom(for: command) else { return }
        switch command {
        case .play:
            play(in: room)
        case .pause:
            if room.playPauseAction == .pause { room.playPause() }
        }
        room.syncWidgetListeningState()
    }

    private func play(in room: ListeningRoomCoordinator) {
        if room.hasWidgetSession {
            if room.playPauseAction == .play {
                room.playPause()
            }
            return
        }
        guard let disc = room.todayDisc(), room.discPresentation(for: disc).canLoad else { return }
        room.loadPlayableDisc(disc)
    }

    /// The shared player for playing from outside Listen (an artist page opened anywhere).
    func roomForPlayback() async -> ListeningRoomCoordinator? {
        if let cached = ListeningRoomSessionStore.shared.room { return cached }
        guard let show = await currentShow() else { return nil }
        let services = playbackDependencies ?? .production
        return await ListeningChromeBootstrapper.roomForWidgetPlayback(
            show: show.show,
            context: show.context,
            catalogService: services.catalogService,
            artistSearchService: services.artistSearchService,
            playbackFactory: services.playbackFactory
        )
    }

    /// A loaded disc stays with the room that is already playing it. Preparing the
    /// current show here would discard that disc. Play with no room loads the
    /// current show so 「今天这张」 can start after a cold launch.
    private func resolveRoom(for command: ListeningWidgetCommand) async -> ListeningRoomCoordinator? {
        if let cached = ListeningRoomSessionStore.shared.room {
            let ready = cached.hasWidgetSession
                || (cached.accessResolved && cached.todayDisc() != nil)
            if ready || command == .pause {
                return cached
            }
        }
        guard let show = await currentShow() else { return nil }
        let services = playbackDependencies ?? .production
        if command == .pause {
            return await ListeningChromeBootstrapper.prepare(
                show: show.show,
                context: show.context,
                catalogService: services.catalogService,
                artistSearchService: services.artistSearchService,
                playbackFactory: services.playbackFactory
            ) ?? ListeningRoomSessionStore.shared.room
        }
        return await ListeningChromeBootstrapper.roomForWidgetPlayback(
            show: show.show,
            context: show.context,
            catalogService: services.catalogService,
            artistSearchService: services.artistSearchService,
            playbackFactory: services.playbackFactory
        )
    }

    private func currentShow() async -> (show: Show, context: ModelContext)? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let selection = (try? context.fetch(FetchDescriptor<CurrentShowSelection>()))?.first
        guard let show = CurrentShowSession().selectCurrentShow(from: shows, manualSelection: selection) else {
            return nil
        }
        return (show, context)
    }
}

struct ListeningWidgetPlaybackDependencies {
    var catalogService: any ListeningMusicCatalogServicing
    var artistSearchService: any ArtistSearchServicing
    var playbackFactory: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing

    static var production: Self {
        Self(
            catalogService: MusicKitListeningCatalogService(),
            artistSearchService: AppleMusicArtistSearchService(),
            playbackFactory: { source in
                if source == .fullCatalog { return MusicKitListeningPlaybackService() }
                return PreviewListeningPlaybackService()
            }
        )
    }
}

@MainActor
enum ListeningHomePlaybackResult {
    case started
    case needsArtistMatch(room: ListeningRoomCoordinator, slotIndex: Int, artistName: String)
    case authorizationDenied
    case authorizationRestricted
    case authorizationNotResolved
    case catalogFailed
    case noPlayableContent
    case playbackFailed
    case noCurrentShow

    var analyticsOutcome: String {
        switch self {
        case .started: "started"
        case .needsArtistMatch: "requires_artist_match"
        case .authorizationDenied, .authorizationRestricted, .authorizationNotResolved: "blocked"
        case .catalogFailed, .noPlayableContent, .playbackFailed, .noCurrentShow: "failed"
        }
    }

    var analyticsReason: String? {
        switch self {
        case .started: nil
        case .needsArtistMatch: "no_playable_disc_unmatched_artist"
        case .authorizationDenied: "music_authorization_denied"
        case .authorizationRestricted: "music_authorization_restricted"
        case .authorizationNotResolved: "music_authorization_not_resolved"
        case .catalogFailed: "catalog_fetch_failed"
        case .noPlayableContent: "no_playable_content"
        case .playbackFailed: "playback_failed"
        case .noCurrentShow: "no_current_show"
        }
    }
}

@MainActor
enum ListeningHomePlaybackCoordinator {
    static func start(
        show: Show,
        context: ModelContext,
        dependencies: ListeningWidgetPlaybackDependencies = .production
    ) async -> ListeningHomePlaybackResult {
        guard show.isAttached else { return .noCurrentShow }
        let room = ListeningChromeBootstrapper.roomForHomePlayback(
            show: show,
            context: context,
            catalogService: dependencies.catalogService,
            artistSearchService: dependencies.artistSearchService,
            playbackFactory: dependencies.playbackFactory
        )

        let initialStatus = dependencies.catalogService.currentAuthorizationStatus()
        ProductAnalytics.capture(.appleMusicAuthorizationStatus(status: initialStatus, source: .currentHome))
        if initialStatus == .notDetermined {
            let requestedStatus = await dependencies.catalogService.requestAuthorization()
            ProductAnalytics.capture(.appleMusicAuthorizationStatus(status: requestedStatus, source: .currentHome))
        }

        let shouldLoad = initialStatus == .notDetermined
            || !room.accessResolved
            || room.access.authorizationStatus != initialStatus
            || room.catalogState == .loading
            || room.isCatalogEnriching
            || room.shouldReloadCatalog(for: show)
            || room.discs.isEmpty
        if shouldLoad {
            await room.load(show: show)
        }
        guard !Task.isCancelled, show.isAttached, room.show?.id == show.id else {
            return .noCurrentShow
        }
        room.setActive(true)

        let unmatchedArtists = room.browseArtists.filter { !$0.isConnected }
        let catalogFailed = room.catalogState == .cacheFailed
        if room.access.authorizationStatus == .authorized {
            if !unmatchedArtists.isEmpty {
                ProductAnalytics.capture(.listeningCatalogMatchFailed(
                    source: .currentHome,
                    stage: "artist_identity",
                    reason: "no_match",
                    failedCount: unmatchedArtists.count
                ))
            }
            if catalogFailed {
                ProductAnalytics.capture(.listeningCatalogMatchFailed(
                    source: .currentHome,
                    stage: "catalog_fetch",
                    reason: "request_failed",
                    failedCount: 1
                ))
            }
        }

        if room.hasWidgetSession {
            if room.playPauseAction == .play {
                room.playPause()
                await room.deck.settle()
            }
            if room.wantsPlayback, room.deck.phase != .failed {
                room.syncWidgetListeningState()
                return .started
            }
            if room.deck.phase == .failed { return .playbackFailed }
        }

        if let disc = playableDisc(in: room) {
            room.loadPlayableDisc(disc)
            await room.deck.settle()
            guard room.wantsPlayback, room.deck.phase != .failed else { return .playbackFailed }
            room.syncWidgetListeningState()
            return .started
        }

        switch room.access.authorizationStatus {
        case .denied:
            return .authorizationDenied
        case .restricted:
            return .authorizationRestricted
        case .notDetermined:
            return .authorizationNotResolved
        case .authorized:
            break
        }

        if let first = unmatchedArtists.first {
            return .needsArtistMatch(room: room, slotIndex: first.slotIndex, artistName: first.name)
        }
        if catalogFailed { return .catalogFailed }
        return .noPlayableContent
    }

    static func playableDisc(in room: ListeningRoomCoordinator) -> ListeningDisc? {
        if let today = room.todayDisc(), room.discPresentation(for: today).canLoad {
            return today
        }
        return room.discs.first { room.discPresentation(for: $0).canLoad }
    }
}
