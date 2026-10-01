import Foundation
import SwiftData

// MARK: - Listening Intent Handler
// 在主 App 进程中执行小组件 AudioPlaybackIntent 请求。

@MainActor
final class ListeningIntentHandler: ListeningIntentHandling {
    static let shared = ListeningIntentHandler()

    private var modelContainer: ModelContainer?

    private init() {}

    func configure(with container: ModelContainer) {
        modelContainer = container
    }

    /// 小组件在 intent 返回后立即刷新：先乐观翻转快照让按键即时响应，
    /// 真实播放在后台完成（App 有后台音频权限），失败或未生效时再按真实状态回写。
    func togglePlayPause() async {
        if let cached = ListeningRoomCache.shared, cached.mechanism.hasDisc {
            cached.syncWidgetListeningState(isPlayingOverride: !cached.isPlaying)
        } else {
            WidgetListeningStore.setPlaying(!(WidgetListeningStore.read()?.isPlaying ?? false))
        }
        Task { await applyToggle() }
    }

    private func applyToggle() async {
        guard let room = await resolveRoom() else {
            WidgetListeningStore.setPlaying(false)
            BeforeShowWidgetKind.reloadAllTimelines()
            return
        }
        if room.mechanism.hasDisc {
            room.playPause()
        } else if let disc = room.defaultDisc {
            room.loadDisc(disc, autoplay: true)
        }
        await room.settlePendingOperation()
        room.syncWidgetListeningState()
    }

    private func resolveRoom() async -> ListeningRoomCoordinator? {
        if let cached = ListeningRoomCache.shared, cached.mechanism.hasDisc {
            return cached
        }
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let selection = (try? context.fetch(FetchDescriptor<CurrentShowSelection>()))?.first
        guard let currentShow = CurrentShowSession().selectCurrentShow(from: shows, manualSelection: selection) else {
            return nil
        }
        return await ListeningChromeBootstrapper.prepare(show: currentShow, context: context) ?? ListeningRoomCache.shared
    }
}
