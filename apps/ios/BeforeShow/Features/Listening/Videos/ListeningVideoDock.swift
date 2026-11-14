import AVKit
import Combine
import MediaPlayer
import Observation
import SwiftUI

/// Owns the artist video player so it outlives the player sheet: dragging the sheet
/// down docks the video into the root mini player and playback carries on.
@MainActor
@Observable
final class ListeningVideoDock {
    static let shared = ListeningVideoDock()

    private(set) var selection: ListeningVideoSelection?
    private(set) var player: AVPlayer?
    private(set) var loadFailed = false
    private(set) var isPlaying = false
    var isExpanded = false

    @ObservationIgnored private let search: any ArtistVideoSearching
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var loadGeneration = 0
    /// Cleared by pause and by losing focus, so a load that returns late stays paused.
    @ObservationIgnored private var autoplayOnLoad = false
    /// Bumped on pause and focus loss so a `.playing` already queued cannot reclaim focus.
    @ObservationIgnored private let playbackEpoch = PlaybackEpoch()
    var playbackEpochValue: Int { playbackEpoch.read() }
    @ObservationIgnored private var statusObservation: AnyCancellable?
    @ObservationIgnored private var itemObservation: AnyCancellable?
    @ObservationIgnored private var endObservation: AnyCancellable?
    @ObservationIgnored private var focusToken: NSObjectProtocol?
    /// Publishes the video to the Lock Screen and Control Center, docked or not.
    @ObservationIgnored private var nowPlaying: MPNowPlayingSession?

    init(search: any ArtistVideoSearching = BilibiliVideoSearchService.shared) {
        self.search = search
    }

    /// A video owns the mini player while it is open or docked, so the bar never flashes back to music.
    var hasVideo: Bool { selection != nil }

    func open(_ selection: ListeningVideoSelection) {
        isExpanded = true
        guard self.selection?.video.id != selection.video.id else { return }
        autoplayOnLoad = true
        if self.selection == nil {
            AppAudioSession.lease(.artistVideo)
            // Music taking over closes the video so the mini player follows it; other sounds only pause.
            focusToken = NotificationCenter.default.addObserver(
                forName: AppAudioSession.focusDidChange, object: nil, queue: nil
            ) { [weak self] notification in
                guard AppAudioSession.takesFocus(notification, from: .artistVideo) else { return }
                let toMusic = notification.object as? AppAudioSession.Owner == .listening
                MainActor.assumeIsolated { toMusic ? self?.close() : self?.pause() }
            }
        }
        self.selection = selection
        load()
    }

    func play(_ video: ArtistVideo) {
        guard selection?.video.id != video.id else { return }
        autoplayOnLoad = true
        selection?.video = video
        load()
    }

    func pause() {
        autoplayOnLoad = false
        playbackEpoch.bump()
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if loadFailed {
            retry()
            return
        }
        guard let player else {
            if hasVideo { retry() }
            return
        }
        if isPlaying {
            pause()
        } else {
            // Take the app's sound before the video starts, not after it is heard.
            AppAudioSession.claimFocus(.artistVideo)
            player.play()
        }
    }

    func retry() {
        autoplayOnLoad = true
        load()
    }

    /// Stops the video and gives the mini player back to the CD.
    func close() {
        loadGeneration &+= 1
        autoplayOnLoad = false
        playbackEpoch.bump()
        loadTask?.cancel()
        statusObservation = nil
        itemObservation = nil
        endObservation = nil
        player?.pause()
        player = nil
        nowPlaying = nil
        isPlaying = false
        loadFailed = false
        isExpanded = false
        guard selection != nil else { return }
        selection = nil
        focusToken.map(NotificationCenter.default.removeObserver)
        focusToken = nil
        AppAudioSession.release(.artistVideo)
    }

    private func load() {
        guard let video = selection?.video else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        statusObservation = nil
        itemObservation = nil
        endObservation = nil
        player?.pause()
        player = nil
        nowPlaying = nil
        isPlaying = false
        loadFailed = false
        let artist = selection?.artist
        loadTask = Task { [search] in
            do {
                let stream = try await search.stream(for: video.bvid)
                // A later pick or a close may land while the address is fetched.
                guard ListeningVideoLoadGate.accepts(generation: generation, current: loadGeneration),
                      !Task.isCancelled, selection?.video.id == video.id else { return }
                let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
                let item = AVPlayerItem(asset: asset)
                item.nowPlayingInfo = [MPMediaItemPropertyTitle: video.title, MPMediaItemPropertyArtist: artist ?? video.author]
                let player = AVPlayer(playerItem: item)
                player.automaticallyWaitsToMinimizeStalling = false
                // With no close button, a finished video hands the mini player back to music.
                endObservation = NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self, ListeningVideoLoadGate.accepts(generation: generation, current: self.loadGeneration) else { return }
                            self.close()
                        }
                    }
                itemObservation = item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        MainActor.assumeIsolated {
                            guard let self, ListeningVideoLoadGate.accepts(generation: generation, current: self.loadGeneration) else { return }
                            guard status == .failed else { return }
                            self.markUnplayable()
                        }
                    }
                let epoch = playbackEpoch
                statusObservation = player.publisher(for: \.timeControlStatus)
                    .map { status in (status, epoch.read()) }
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status, emittedEpoch in
                        MainActor.assumeIsolated {
                            self?.consumeTimeControlStatus(
                                status, player: player, generation: generation, emittedEpoch: emittedEpoch
                            )
                        }
                    }
                self.player = player
                publishNowPlaying(for: player, item: item, cover: video.coverURL)
                if item.status == .failed {
                    markUnplayable()
                    return
                }
                guard ListeningVideoLoadGate.shouldStartPlayback(
                    autoplay: autoplayOnLoad,
                    generation: generation,
                    current: loadGeneration,
                    cancelled: Task.isCancelled,
                    videoID: video.id,
                    selectedID: selection?.video.id
                ) else { return }
                AppAudioSession.claimFocus(.artistVideo)
                player.play()
                _ = await nowPlaying?.becomeActiveIfPossible()
            } catch {
                guard ListeningVideoLoadGate.accepts(generation: generation, current: loadGeneration), !Task.isCancelled else { return }
                loadFailed = true
            }
        }
    }

    /// A `.playing` queued before pause or focus loss must not run after that pause.
    /// Focus follows the player as it is now, so a system-player resume still claims it.
    func consumeTimeControlStatus(
        _ reported: AVPlayer.TimeControlStatus,
        player: AVPlayer?,
        generation: Int,
        emittedEpoch: Int
    ) {
        guard ListeningVideoLoadGate.accepts(generation: generation, current: loadGeneration) else { return }
        guard !loadFailed else { return }
        guard emittedEpoch == playbackEpoch.read() else { return }
        let actual = player?.timeControlStatus ?? .paused
        if reported == .playing, actual == .playing {
            AppAudioSession.claimFocus(.artistVideo)
        }
        isPlaying = actual != .paused
    }

    private func markUnplayable() {
        loadFailed = true
        isPlaying = false
        player?.pause()
    }

    private func publishNowPlaying(for player: AVPlayer, item: AVPlayerItem, cover: URL?) {
        let session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = true
        let commands = session.remoteCommandCenter
        commands.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayback() } }
            return .success
        }
        commands.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayback() } }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        nowPlaying = session
        guard let cover else { return }
        Task {
            guard let image = await ShowCoverImageCache.shared.image(from: cover) else { return }
            item.nowPlayingInfo?[MPMediaItemPropertyArtwork] = PreviewListeningPlaybackService.makeArtwork(image)
        }
    }
}

private final class PlaybackEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() {
        lock.lock()
        value &+= 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// A load may return after pause, focus loss, or a newer pick. Only the current generation may change the dock.
enum ListeningVideoLoadGate {
    static func accepts(generation: Int, current: Int) -> Bool {
        generation == current
    }

    static func shouldStartPlayback(
        autoplay: Bool,
        generation: Int,
        current: Int,
        cancelled: Bool,
        videoID: String,
        selectedID: String?
    ) -> Bool {
        autoplay && accepts(generation: generation, current: current) && !cancelled && videoID == selectedID
    }
}
