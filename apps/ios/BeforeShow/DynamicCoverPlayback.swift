import AVFoundation
import SwiftUI
import UIKit

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// muted, so the app stays on `ambient` + `mixWithOthers` and never stops the
/// user's music. Views that intentionally play sound switch to `playback` while
/// they are on screen.
enum AppAudioSession {
    static func configureAmbient() {
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    static func configureSoundPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}

/// A borderless, muted AVPlayer surface used by dynamic covers.
struct DynamicCoverPlaybackView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    var muted = true

    func makeUIView(context: Context) -> DynamicCoverPlayerView {
        DynamicCoverPlayerView()
    }

    func updateUIView(_ view: DynamicCoverPlayerView, context: Context) {
        view.configure(url: url, isPlaying: isPlaying, muted: muted)
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
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL, isPlaying: Bool, muted: Bool) {
        player.isMuted = muted
        if loadedURL != url {
            loadedURL = url
            removeEndObserver()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
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
