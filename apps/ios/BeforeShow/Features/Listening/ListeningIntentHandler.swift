import Foundation
import SwiftData

// MARK: - Listening Intent Handler
// 在主 App 进程中执行小组件的播放或暂停。命令串行进入「听」模块，不改写快照来假装已经生效。

@MainActor
final class ListeningIntentHandler: ListeningIntentHandling {
    static let shared = ListeningIntentHandler()

    private var modelContainer: ModelContainer?
    private var commandChain: Task<Void, Never> = Task {}

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
            if room.playPauseAction == .pause, !room.mechanism.isAutomatic {
                room.playPause()
            }
        }
        await room.settlePendingOperation()
        room.syncWidgetListeningState()
    }

    private func play(in room: ListeningRoomCoordinator) {
        if room.mechanism.isAutomatic { return }
        if room.hasLoadedDisc {
            if room.playPauseAction == .play {
                room.playPause()
            }
            return
        }
        guard let disc = room.livePreviewDisc, room.discPresentation(for: disc).canLoad else { return }
        room.loadDisc(disc, autoplay: true)
    }

    /// A loaded disc stays with the room that is already playing it. Preparing the
    /// current show here would discard that disc.
    private func resolveRoom(for command: ListeningWidgetCommand) async -> ListeningRoomCoordinator? {
        if let cached = ListeningRoomSessionStore.shared.room {
            let ownsSession = cached.hasLoadedDisc || cached.busy || cached.mechanism.isAutomatic
            if ownsSession || command == .pause || cached.show != nil {
                return cached
            }
        }
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let selection = (try? context.fetch(FetchDescriptor<CurrentShowSelection>()))?.first
        guard let currentShow = CurrentShowSession().selectCurrentShow(from: shows, manualSelection: selection) else {
            return nil
        }
        return await ListeningChromeBootstrapper.prepare(show: currentShow, context: context)
            ?? ListeningRoomSessionStore.shared.room
    }
}
