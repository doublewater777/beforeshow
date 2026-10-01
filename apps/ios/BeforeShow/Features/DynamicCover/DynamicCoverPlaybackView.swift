import AVFoundation
import SwiftUI
import UIKit

/// Dynamic covers are visual decoration. Their player item must contain video
/// only so starting a cover can never contend with Listening for audio output.
@MainActor
enum DynamicCoverPlaybackPolicy {
    static func includes(mediaType: AVMediaType) -> Bool {
        mediaType == .video
    }

    static func makeVideoOnlyItem(url: URL) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        guard let sourceVideoTrack = tracks.first(where: { includes(mediaType: $0.mediaType) }) else {
            throw DynamicCoverPlaybackError.missingVideoTrack
        }
        let sourceTimeRange = try await sourceVideoTrack.load(.timeRange)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw DynamicCoverPlaybackError.unableToCreateVideoTrack
        }

        try videoTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        return AVPlayerItem(asset: composition)
    }
}

private enum DynamicCoverPlaybackError: Error {
    case missingVideoTrack
    case unableToCreateVideoTrack
}

/// A borderless, always-muted AVPlayer surface used by dynamic covers.
///
/// Covers are decorative and must never compete with listening playback, so
/// they have no sound control and leave the app-wide ambient audio policy alone.
struct DynamicCoverPlaybackView: View {
    let url: URL
    let isPlaying: Bool

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DynamicCoverPlayerSurface(
            url: url,
            isPlaying: isPlaying && scenePhase == .active
        )
    }
}

private struct DynamicCoverPlayerSurface: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> DynamicCoverPlayerView {
        DynamicCoverPlayerView()
    }

    func updateUIView(_ view: DynamicCoverPlayerView, context: Context) {
        view.configure(url: url, isPlaying: isPlaying)
    }

    static func dismantleUIView(_ view: DynamicCoverPlayerView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class DynamicCoverPlayerView: UIView {
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadedURL: URL?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Keep mute as a second line of defense. The item itself is video-only.
        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Called from `updateUIView`. With `AVPlayer.isObservationEnabled`, any
    /// player access here is tracked by SwiftUI, and the resulting state change
    /// re-invalidates the view. Only touch the player when the request changes,
    /// otherwise pause/play re-triggers updates forever and hangs the main thread.
    func configure(url: URL, isPlaying: Bool) {
        let urlChanged = loadedURL != url
        if urlChanged {
            loadedURL = url
            isPlayingRequested = isPlaying
            loadTask?.cancel()
            removeEndObserver()
            player.pause()
            player.replaceCurrentItem(with: nil)

            loadTask = Task { @MainActor [weak self] in
                do {
                    let item = try await DynamicCoverPlaybackPolicy.makeVideoOnlyItem(url: url)
                    try Task.checkCancellation()
                    guard let self, self.loadedURL == url else { return }
                    self.install(item)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.loadedURL == url else { return }
                    self.player.replaceCurrentItem(with: nil)
                }
            }
            return
        }

        guard isPlayingRequested != isPlaying else { return }
        isPlayingRequested = isPlaying
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        isPlayingRequested = false
        loadTask?.cancel()
        loadTask = nil
        player.pause()
        removeEndObserver()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    private var isPlayingRequested = false

    private func install(_ item: AVPlayerItem) {
        removeEndObserver()
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player.seek(to: .zero)
                if self?.isPlayingRequested == true {
                    self?.player.play()
                }
            }
        }
        if isPlayingRequested {
            player.play()
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
