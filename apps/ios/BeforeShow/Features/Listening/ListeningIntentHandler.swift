import Foundation
import SwiftData

enum ListeningHomePlaybackResult: Equatable {
    case playbackRequested
    case authorizationRequired(status: ListeningMusicAuthorizationStatus)
    case artistMatchRequired(slotIndex: Int, unmatchedCount: Int, artistCount: Int)
    case unavailable(reason: String)
}

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

    /// Home requests Music permission when needed and returns a concrete reason
    /// when today's record cannot be started. Widget intents keep their existing
    /// no-prompt behavior through perform(_:).
    func playFromHome(show: Show, context: ModelContext) async -> ListeningHomePlaybackResult {
        let services = playbackDependencies ?? .production
        let room = await ListeningChromeBootstrapper.roomForWidgetPlayback(
            show: show,
            context: context,
            catalogService: services.catalogService,
            artistSearchService: services.artistSearchService,
            playbackFactory: services.playbackFactory
        )

        await room.refreshMusicAccess()
        let initialStatus = room.access.authorizationStatus
        ProductAnalytics.capture(.listeningAuthorizationStatus(
            source: "home_primary_action",
            status: initialStatus,
            stage: "before_request"
        ))
        if initialStatus == .notDetermined {
            await room.authorize()
            ProductAnalytics.capture(.listeningAuthorizationStatus(
                source: "home_primary_action",
                status: room.access.authorizationStatus,
                stage: "after_request"
            ))
        }

        guard room.access.authorizationStatus == .authorized else {
            return .authorizationRequired(status: room.access.authorizationStatus)
        }

        if room.shouldReloadCatalog(for: show) {
            await room.load(show: show)
        }
        guard room.show?.id == show.id else {
            return .unavailable(reason: "show_unavailable")
        }

        if let disc = room.todayDisc(), room.discPresentation(for: disc).canLoad {
            room.loadPlayableDisc(disc)
            guard room.loadedDisc?.id == disc.id, room.wantsPlayback else {
                return .unavailable(reason: "playback_not_started")
            }
            return .playbackRequested
        }

        let unmatched = room.browseArtists.filter {
            !$0.isConnected && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let first = unmatched.first {
            return .artistMatchRequired(
                slotIndex: first.slotIndex,
                unmatchedCount: unmatched.count,
                artistCount: room.browseArtists.count
            )
        }

        let reason: String
        switch room.catalogState {
        case .loading: reason = "catalog_loading"
        case .ready: reason = "no_playable_disc"
        case .unmatched: reason = "artist_unmatched"
        case .cacheFailed: reason = "catalog_failed"
        case .unavailable: reason = "catalog_unavailable"
        }
        return .unavailable(reason: reason)
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
