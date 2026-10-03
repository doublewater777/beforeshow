import Foundation
import MediaPlayer

@MainActor
final class ListeningRemoteCommandBridge {
    static let shared = ListeningRemoteCommandBridge()

    private weak var controller: ListeningPlaybackController?
    private var itemsBySongID: [String: ListeningPlaybackItem] = [:]

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.previous() }
            return .success
        }
    }

    func attach(controller: ListeningPlaybackController, items: [ListeningPlaybackItem]) {
        self.controller = controller
        itemsBySongID = Dictionary(uniqueKeysWithValues: items.map { ($0.songID, $0) })
    }

    func detach(controller: ListeningPlaybackController) {
        guard self.controller === controller else { return }
        self.controller = nil
        itemsBySongID = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func update(
        controller: ListeningPlaybackController,
        sample: ListeningPlaybackSample
    ) {
        guard self.controller === controller,
              let item = itemsBySongID[sample.songID] else { return }
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyExternalContentIdentifier: sample.songID,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: sample.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: sample.isPlaying ? 1.0 : 0.0
        ]
        if let title = item.title { info[MPMediaItemPropertyTitle] = title }
        if let artistName = item.artistName { info[MPMediaItemPropertyArtist] = artistName }
        if let duration = sample.duration ?? item.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func play() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.play() }
    }

    private func pause() {
        try? controller?.pause()
    }

    private func togglePlayPause() {
        guard let controller else { return }
        if controller.wantsPlayback {
            try? controller.pause()
        } else {
            Task { @MainActor in try? await controller.play() }
        }
    }

    private func next() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.skipToNext() }
    }

    private func previous() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.skipToPrevious() }
    }

    func playForTesting() async throws {
        try await controller?.play()
    }

    func togglePlayPauseForTesting() async throws {
        guard let controller else { return }
        if controller.wantsPlayback {
            try controller.pause()
        } else {
            try await controller.play()
        }
    }

    func pauseForTesting() throws {
        try controller?.pause()
    }

    func nextForTesting() async throws {
        try await controller?.skipToNext()
    }

    @discardableResult
    func refreshForTesting(now: Date = Date()) throws -> ListeningPlaybackState? {
        try controller?.refresh(now: now)
    }
}
