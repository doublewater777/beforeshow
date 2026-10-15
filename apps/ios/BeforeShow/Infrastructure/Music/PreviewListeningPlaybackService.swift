import AVFoundation
import MediaPlayer
import UIKit

/// 30-second previews are DRM-free, so they play on AVFoundation directly.
/// `MPNowPlayingSession` publishes Now Playing for this player and owns its
/// remote commands; transport state comes from AVFoundation Observation.
@MainActor
@Observable
final class PreviewListeningPlaybackService: ListeningPlaybackServicing {
    let source = ListeningPlaybackSource.preview
    private let owner: AppAudioSession.Owner
    private let player: AVQueuePlayer
    private let nowPlaying: MPNowPlayingSession
    private var queue: [ListeningPlaybackItem] = []
    private var itemIndexes: [ObjectIdentifier: Int] = [:]
    private var isInterrupted = false
    // User intent is needed while AVPlayer is paused by an interruption.
    private var playbackRequested = false
    @ObservationIgnored private var ownsAudioSession = false
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var commandAvailabilityTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworks: [URL: MPMediaItemArtwork] = [:]

    init(player: AVQueuePlayer = AVQueuePlayer(), owner: AppAudioSession.Owner = .listening) {
        self.player = player
        self.owner = owner
        nowPlaying = MPNowPlayingSession(players: [player])
        nowPlaying.automaticallyPublishesNowPlayingInfo = true
        registerRemoteCommands()
        observeCommandAvailability()
        observeAudioSession()
        audioObservers.append(AppAudioSession.observeFocusLoss(of: owner) { [weak self] in
            self?.pause()
        })
    }

    isolated deinit {
        resumeTask?.cancel()
        commandAvailabilityTask?.cancel()
        artworkTask?.cancel()
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
    }

    var phase: ListeningPlaybackTransportPhase {
        guard let item = player.currentItem, item.status != .failed else { return .stopped }
        switch player.timeControlStatus {
        case .playing: return .playing
        case .waitingToPlayAtSpecifiedRate: return .waiting
        case .paused: return isInterrupted && playbackRequested ? .interrupted : .paused
        @unknown default: return .paused
        }
    }

    var currentSongID: String? {
        currentIndex.map { queue[$0].songID }
    }

    /// AVQueuePlayer drops each item as it finishes; an empty player with a
    /// loaded queue has played through the last preview.
    var hasEnded: Bool {
        !queue.isEmpty && player.currentItem == nil
    }

    var failure: ListeningPlaybackError? {
        guard player.currentItem?.status == .failed, let songID = currentSongID else { return nil }
        return .songUnavailable(songID)
    }

    var queuedSongIDs: [String] {
        queue.map(\.songID)
    }

    var currentTime: TimeInterval {
        guard player.currentItem != nil else {
            return hasEnded ? currentDuration ?? 0 : 0
        }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var currentDuration: TimeInterval? {
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            return seconds
        }
        return currentIndex.flatMap { queue[$0].duration }
    }

    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws {
        pause()
        let playable = items.filter { $0.previewURL != nil }
        guard !playable.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        queue = playable
        let start = songID.flatMap { id in playable.firstIndex { $0.songID == id } } ?? 0
        rebuild(startingAt: start)
        // A position kept from full playback can lie beyond the 30-second preview.
        if time > 0, let asset = player.currentItem?.asset,
           let length = try? await asset.load(.duration).seconds, time < length {
            _ = await player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
    }

    func play() async throws {
        try Task.checkCancellation()
        // A finished or failed queue is reloaded by its owner, never revived here.
        guard let item = player.currentItem, item.status != .failed else {
            throw ListeningPlaybackError.emptyQueue
        }
        playbackRequested = true
        ownsAudioSession = true
        AppAudioSession.lease(owner)
        await AppAudioSession.waitForPendingOperations()
        try Task.checkCancellation()
        guard playbackRequested else { return }
        AppAudioSession.claimFocus(owner)
        player.play()
        Task { [weak self] in
            guard let self, self.playbackRequested else { return }
            _ = await self.nowPlaying.becomeActiveIfPossible()
        }
    }

    func pause() {
        playbackRequested = false
        resumeTask?.cancel()
        player.pause()
    }

    func skipToNext() async throws {
        guard let index = currentIndex, index + 1 < queue.count else {
            throw ListeningPlaybackError.queueBoundary
        }
        player.advanceToNextItem()
    }

    func skipToPrevious() async throws {
        guard let index = currentIndex, index > 0 else {
            throw ListeningPlaybackError.queueBoundary
        }
        move(to: index - 1)
    }

    func skip(to songID: String) async throws {
        guard let index = queue.firstIndex(where: { $0.songID == songID }) else {
            throw ListeningPlaybackError.songUnavailable(songID)
        }
        move(to: index)
    }

    func stop() {
        pause()
        player.removeAllItems()
        queue = []
        itemIndexes = [:]
        artworkTask?.cancel()
        if ownsAudioSession {
            ownsAudioSession = false
            AppAudioSession.release(owner)
        }
    }

    private var currentIndex: Int? {
        guard !queue.isEmpty else { return nil }
        guard let item = player.currentItem else { return queue.count - 1 }
        return itemIndexes[ObjectIdentifier(item)]
    }

    private func move(to index: Int) {
        let continuesPlaying = phase.isActive
        rebuild(startingAt: index)
        if continuesPlaying {
            player.play()
        }
    }

    private func rebuild(startingAt index: Int) {
        player.removeAllItems()
        itemIndexes = [:]
        guard queue.indices.contains(index) else { return }
        var previous: AVPlayerItem?
        for queueIndex in index..<queue.count {
            guard let url = queue[queueIndex].previewURL else { continue }
            let item = AVPlayerItem(url: url)
            item.nowPlayingInfo = nowPlayingInfo(for: queue[queueIndex])
            itemIndexes[ObjectIdentifier(item)] = queueIndex
            player.insert(item, after: previous)
            previous = item
        }
        loadArtwork()
    }

    private func nowPlayingInfo(for entry: ListeningPlaybackItem) -> [String: Any] {
        var info: [String: Any] = [:]
        if let title = entry.title { info[MPMediaItemPropertyTitle] = title }
        if let artist = entry.artistName { info[MPMediaItemPropertyArtist] = artist }
        if let album = entry.albumTitle { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork = entry.artworkURL.flatMap({ artworks[$0] }) { info[MPMediaItemPropertyArtwork] = artwork }
        return info
    }

    /// Fetches cover art for queued items, current item first, then refreshes their Now Playing info.
    private func loadArtwork() {
        artworkTask?.cancel()
        let start = currentIndex ?? 0
        var seen = Set(artworks.keys)
        let missing = (queue[start...] + queue[..<start]).compactMap(\.artworkURL).filter { seen.insert($0).inserted }
        guard !missing.isEmpty else { return }
        artworkTask = Task { [weak self] in
            for url in missing {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { continue }
                guard let self, !Task.isCancelled else { return }
                self.artworks[url] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                for item in self.player.items() {
                    guard let index = self.itemIndexes[ObjectIdentifier(item)],
                          self.queue[index].artworkURL == url else { continue }
                    item.nowPlayingInfo = self.nowPlayingInfo(for: self.queue[index])
                }
            }
        }
    }

    /// Greys out Previous/Next on the Lock Screen at either end of the queue.
    private func observeCommandAvailability() {
        commandAvailabilityTask = Task { [weak self] in
            let positions = Observations { [weak self] () -> (index: Int?, count: Int)? in
                guard let self else { return nil }
                return (self.currentIndex, self.queue.count)
            }
            for await position in positions {
                guard let self, let position else { return }
                let commands = self.nowPlaying.remoteCommandCenter
                commands.previousTrackCommand.isEnabled = (position.index ?? 0) > 0
                commands.nextTrackCommand.isEnabled = position.index.map { $0 + 1 < position.count } ?? false
            }
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
            let options = AVAudioSession.InterruptionOptions(
                rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            let reason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            // Delivered on return from suspension; no ended notification follows.
            guard reason != AVAudioSession.InterruptionReason.appWasSuspended.rawValue else { return }
            let routeDisconnected = reason == AVAudioSession.InterruptionReason.routeDisconnected.rawValue
            MainActor.assumeIsolated {
                self?.handleInterruption(type, options: options, routeDisconnected: routeDisconnected)
            }
        })
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    private func handleInterruption(
        _ type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions,
        routeDisconnected: Bool
    ) {
        switch type {
        case .began:
            resumeTask?.cancel()
            isInterrupted = true
            player.pause()
            if routeDisconnected { pause() }
        case .ended:
            guard isInterrupted else { return }
            isInterrupted = false
            guard playbackRequested, player.currentItem != nil, options.contains(.shouldResume) else {
                pause()
                return
            }
            resumeTask = Task { [weak self] in
                guard let self else { return }
                try? await self.play()
            }
        @unknown default:
            break
        }
    }

    private func registerRemoteCommands() {
        let commands = nowPlaying.remoteCommandCenter
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.play() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.phase.isActive || self.phase == .interrupted { self.pause() } else { try? await self.play() }
            }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.skipToNext() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.skipToPrevious() }
            return .success
        }
    }
}
