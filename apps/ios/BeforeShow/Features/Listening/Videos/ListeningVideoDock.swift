import AVKit
import Combine
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
    @ObservationIgnored private var statusObservation: AnyCancellable?
    @ObservationIgnored private var endObservation: AnyCancellable?
    @ObservationIgnored private var focusToken: NSObjectProtocol?

    init(search: any ArtistVideoSearching = BilibiliVideoSearchService.shared) {
        self.search = search
    }

    var isDocked: Bool { selection != nil && !isExpanded }

    func open(_ selection: ListeningVideoSelection) {
        isExpanded = true
        guard self.selection?.video.id != selection.video.id else { return }
        if self.selection == nil {
            AppAudioSession.lease(.artistVideo)
            focusToken = AppAudioSession.observeFocusLoss(of: .artistVideo) { [weak self] in
                self?.close()
            }
        }
        self.selection = selection
        load()
    }

    func play(_ video: ArtistVideo) {
        guard selection?.video.id != video.id else { return }
        selection?.video = video
        load()
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Take the app's sound before the video starts, not after it is heard.
            AppAudioSession.claimFocus(.artistVideo)
            player.play()
        }
    }

    func retry() { load() }

    /// Stops the video and gives the mini player back to the CD.
    func close() {
        loadTask?.cancel()
        statusObservation = nil
        endObservation = nil
        player?.pause()
        player = nil
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
        loadTask?.cancel()
        statusObservation = nil
        endObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
        loadFailed = false
        loadTask = Task { [search] in
            do {
                let stream = try await search.stream(for: video.bvid)
                // A later pick or a close may land while the address is fetched.
                guard !Task.isCancelled, selection?.video.id == video.id else { return }
                let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                // With no close button, a finished video hands the mini player back to music.
                endObservation = NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.close() }
                statusObservation = player.publisher(for: \.timeControlStatus)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        // Resuming from any control reclaims the app's sound.
                        if status == .playing { AppAudioSession.claimFocus(.artistVideo) }
                        self?.isPlaying = status != .paused
                    }
                self.player = player
                AppAudioSession.claimFocus(.artistVideo)
                player.play()
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }
}
