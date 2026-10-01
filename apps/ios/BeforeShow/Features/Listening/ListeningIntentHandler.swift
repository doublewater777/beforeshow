import Foundation
import SwiftData
import UIKit

// MARK: - Listening Intent Handler
// 在主 App 进程中执行小组件 AudioPlaybackIntent 请求。

@MainActor
final class ListeningIntentHandler: ListeningIntentHandling {
    static let shared = ListeningIntentHandler()

    private init() {}

    func togglePlayPause() async {
        guard let room = await resolveOrBootstrapRoom() else { return }
        room.playPause()
        room.syncWidgetListeningState()
    }

    func skipToNext() async {
        guard let room = await resolveOrBootstrapRoom() else { return }
        room.skip(1)
        room.syncWidgetListeningState()
    }

    func skipToPrevious() async {
        guard let room = await resolveOrBootstrapRoom() else { return }
        room.skip(-1)
        room.syncWidgetListeningState()
    }

    private func resolveOrBootstrapRoom() async -> ListeningRoomCoordinator? {
        if let cached = ListeningRoomCache.shared, cached.mechanism.hasDisc {
            return cached
        }

        guard let delegate = (UIApplication.shared.delegate as? BeforeShowAppDelegate) ?? BeforeShowAppDelegate.shared,
              let container = delegate.modelContainer else {
            return nil
        }
        let context = ModelContext(container)
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let selection = (try? context.fetch(FetchDescriptor<CurrentShowSelection>()))?.first
        guard let currentShow = CurrentShowSession().selectCurrentShow(from: shows, manualSelection: selection) else {
            return nil
        }

        let room = await ListeningChromeBootstrapper.prepare(show: currentShow, context: context)
        if let room, room.mechanism.hasDisc {
            return room
        }

        // 若尚未装碟，尝试自动装入并播放第一张合辑/专辑
        if let targetRoom = room ?? ListeningRoomCache.shared {
            if let firstDisc = targetRoom.compilationDiscs.first ?? targetRoom.discs.first {
                targetRoom.loadDisc(firstDisc, autoplay: true)
                return targetRoom
            }
        }
        return room
    }
}
