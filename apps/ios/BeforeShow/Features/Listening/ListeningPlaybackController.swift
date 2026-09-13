import Foundation
import MediaPlayer

@MainActor
final class ListeningPlaybackController {
    private let service: ListeningPlaybackServicing
    private let evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    private var stateMachine = ListeningPlaybackStateMachine()
    private var observationTask: Task<Void, Never>?

    var state: ListeningPlaybackState { stateMachine.state }

    init(
        service: ListeningPlaybackServicing,
        evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    ) {
        self.service = service
        self.evidenceCoordinator = evidenceCoordinator
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String? = nil,
        now: Date = Date()
    ) async throws {
        observationTask?.cancel()
        observationTask = nil
        stateMachine.handle(.prepareStarted(source: source))
        do {
            try await service.prepare(
                items: items,
                source: source,
                startingAtSongID: startingAtSongID
            )
            guard service.snapshot(observedAt: now) != nil else {
                throw ListeningPlaybackError.songUnavailable(startingAtSongID ?? items.first?.songID ?? "")
            }
            ListeningRemoteCommandBridge.shared.attach(controller: self, items: items)
            _ = try refresh(now: now)
        } catch {
            stateMachine.handle(.failed)
            throw error
        }
    }

    func play(now: Date = Date()) async throws {
        do {
            try await service.play()
            _ = try refresh(now: now)
            startObservation()
        } catch {
            stateMachine.handle(.failed)
            throw error
        }
    }

    func pause(now: Date = Date()) throws {
        service.pause()
        _ = try refresh(now: now)
        observationTask?.cancel()
        observationTask = nil
    }

    func skipToNext(now: Date = Date()) async throws {
        _ = try refresh(now: now)
        try await service.skipToNext()
        evidenceCoordinator.breakContinuity()
        _ = try refresh(now: now)
    }

    func skipToPrevious(now: Date = Date()) async throws {
        _ = try refresh(now: now)
        try await service.skipToPrevious()
        evidenceCoordinator.breakContinuity()
        _ = try refresh(now: now)
    }

    func seek(to time: TimeInterval, now: Date = Date()) throws {
        _ = try refresh(now: now)
        service.seek(to: time)
        evidenceCoordinator.breakContinuity()
    }

    @discardableResult
    func refresh(now: Date = Date()) throws -> ListeningPlaybackState {
        // A transport/resource failure is a user-visible playback state, not a
        // reason to tear down the physical disc or reset the selected track.
        // The coordinator can therefore keep the disc in place and project a
        // retry action next to the player.
        if service.failure != nil {
            stateMachine.handle(.failed)
            return state
        }
        guard let sample = service.snapshot(observedAt: now) else {
            return state
        }
        stateMachine.handle(.sample(sample))
        _ = try evidenceCoordinator.ingest(sample, at: now)
        ListeningRemoteCommandBridge.shared.update(sample: sample)
        return state
    }

    func stop(now: Date = Date()) throws {
        observationTask?.cancel()
        observationTask = nil
        defer {
            service.stop()
            evidenceCoordinator.breakContinuity()
            stateMachine.handle(.reset)
            ListeningRemoteCommandBridge.shared.detach(controller: self)
        }
        _ = try refresh(now: now)
    }

    private func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self {
                    _ = try? self.refresh(now: Date())
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }
}

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

    func update(sample: ListeningPlaybackSample) {
        guard let item = itemsBySongID[sample.songID] else { return }
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
        switch controller.state {
        case .playing:
            try? controller.pause()
        default:
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
        switch controller.state {
        case .playing:
            try controller.pause()
        default:
            try await controller.play()
        }
    }
}
