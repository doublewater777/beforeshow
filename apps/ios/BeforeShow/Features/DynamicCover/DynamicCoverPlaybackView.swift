import AVFoundation
import SwiftUI
import UIKit

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
    private var loadedURL: URL?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
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
            removeEndObserver()
            let item = AVPlayerItem(url: url)
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
        }
        guard urlChanged || isPlayingRequested != isPlaying else { return }
        isPlayingRequested = isPlaying
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        isPlayingRequested = false
        player.pause()
        removeEndObserver()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    private var isPlayingRequested = false

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
